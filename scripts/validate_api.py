#!/usr/bin/env python3
"""Smoke-test the Visual Assistant REST API with the bundled demo images.

This script intentionally uses only the Python standard library so reviewers can
run it without setting up a Python package manager.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Optional


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IMAGE_DIR = ROOT / "priv" / "demo" / "uploads"


class ApiError(RuntimeError):
    def __init__(self, method: str, url: str, status: int, body: bytes) -> None:
        self.method = method
        self.url = url
        self.status = status
        self.body = body
        super().__init__(f"{method} {url} returned HTTP {status}: {body[:300]!r}")


class Client:
    def __init__(self, base_url: str, timeout: float) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def get_bytes(self, path: str) -> tuple[int, dict[str, str], bytes]:
        return self._request("GET", path)

    def post_json(self, path: str, payload: dict[str, Any]) -> tuple[int, dict[str, str], bytes]:
        body = json.dumps(payload).encode("utf-8")
        return self._request(
            "POST",
            path,
            body=body,
            headers={"content-type": "application/json"},
        )

    def post_multipart_image(self, path: str, image_path: Path) -> tuple[int, dict[str, str], bytes]:
        boundary = f"----inkit-smoke-{time.time_ns()}"
        content_type = mimetypes.guess_type(image_path.name)[0] or "application/octet-stream"
        image_bytes = image_path.read_bytes()

        body = b"".join(
            [
                f"--{boundary}\r\n".encode("ascii"),
                (
                    'Content-Disposition: form-data; name="image"; '
                    f'filename="{image_path.name}"\r\n'
                ).encode("utf-8"),
                f"Content-Type: {content_type}\r\n\r\n".encode("ascii"),
                image_bytes,
                f"\r\n--{boundary}--\r\n".encode("ascii"),
            ]
        )

        return self._request(
            "POST",
            path,
            body=body,
            headers={"content-type": f"multipart/form-data; boundary={boundary}"},
        )

    def _request(
        self,
        method: str,
        path: str,
        *,
        body: Optional[bytes] = None,
        headers: Optional[dict[str, str]] = None,
    ) -> tuple[int, dict[str, str], bytes]:
        url = f"{self.base_url}{path}"
        request = urllib.request.Request(url, data=body, method=method, headers=headers or {})

        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return response.status, dict(response.headers), response.read()
        except urllib.error.HTTPError as error:
            raise ApiError(method, url, error.code, error.read()) from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://localhost:4000")
    parser.add_argument("--image-dir", type=Path, default=DEFAULT_IMAGE_DIR)
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()

    client = Client(args.base_url, args.timeout)
    image_paths = [args.image_dir / "kitchen.jpg", args.image_dir / "bathroom.jpg"]

    for image_path in image_paths:
        require(image_path.exists(), f"missing sample image: {image_path}")

    print(f"Checking app at {args.base_url}")
    wait_for_app(client)

    validate_seeded_demo_records(client)

    for image_path in image_paths:
        image_id = validate_upload(client, image_path)
        validate_image_download(client, image_id)
        validate_chat(client, image_id, "What style and materials do you see?")
        validate_stream(client, image_id, "What would you improve?")
        validate_history(client, image_id)

    print("API smoke test passed")
    return 0


def wait_for_app(client: Client) -> None:
    deadline = time.monotonic() + client.timeout
    last_error: Optional[Exception] = None

    while time.monotonic() < deadline:
        try:
            status, _headers, body = client.get_bytes("/")
            require(status == 200, f"expected GET / to return 200, got {status}")
            require(b"Visual Assistant" in body, "GET / did not look like the app shell")
            print("  ok: app shell is reachable")
            return
        except Exception as error:  # noqa: BLE001 - report final startup failure.
            last_error = error
            time.sleep(0.5)

    raise AssertionError(f"app did not become reachable: {last_error}")


def validate_seeded_demo_records(client: Client) -> None:
    seeded_ids = ["img_demo_kitchen", "img_demo_bathroom"]
    found = 0

    for image_id in seeded_ids:
        try:
            status, headers, body = client.get_bytes(f"/images/{image_id}")
        except ApiError as error:
            if error.status == 404:
                continue
            raise

        require(status == 200, f"expected seeded {image_id} download to return 200")
        require_header_contains(headers, "content-type", "image/jpeg")
        require(len(body) > 1_000, f"seeded {image_id} download was unexpectedly small")
        found += 1

    if found == len(seeded_ids):
        print("  ok: bundled demo database and images are available")
    else:
        print("  note: bundled demo records were not present; continuing with upload flow")


def validate_upload(client: Client, image_path: Path) -> str:
    status, _headers, body = client.post_multipart_image("/upload", image_path)
    payload = decode_json(body)

    require(status == 201, f"expected upload status 201, got {status}")
    image = payload.get("image", {})
    image_id = image.get("id")
    require(isinstance(image_id, str) and image_id.startswith("img_"), "upload returned bad image id")
    require(image.get("original_filename") == image_path.name, "upload returned wrong filename")
    require_chat_completion(payload.get("analysis"), expected_object="chat.completion")
    print(f"  ok: uploaded {image_path.name} as {image_id}")
    return image_id


def validate_image_download(client: Client, image_id: str) -> None:
    status, headers, body = client.get_bytes(f"/images/{image_id}")

    require(status == 200, f"expected image download status 200, got {status}")
    require_header_contains(headers, "content-type", "image/")
    require(len(body) > 1_000, "downloaded image was unexpectedly small")
    print(f"  ok: downloaded {image_id}")


def validate_chat(client: Client, image_id: str, question: str) -> dict[str, Any]:
    status, _headers, body = client.post_json(f"/chat/{image_id}", {"question": question})
    payload = decode_json(body)

    require(status == 200, f"expected chat status 200, got {status}")
    require_chat_completion(payload, expected_object="chat.completion")
    require(payload["choices"][0]["message"]["content"], "chat response content was empty")
    print(f"  ok: non-streaming chat for {image_id}")
    return payload


def validate_stream(client: Client, image_id: str, question: str) -> None:
    status, headers, body = client.post_json(f"/chat/{image_id}/stream", {"question": question})
    text = body.decode("utf-8")
    events = parse_sse_data_events(text)
    chunks = [json.loads(event) for event in events if event != "[DONE]"]

    require(status == 200, f"expected stream status 200, got {status}")
    require_header_contains(headers, "content-type", "text/event-stream")
    require(events and events[-1] == "[DONE]", "SSE stream did not end with data: [DONE]")
    require(chunks, "SSE stream did not include JSON chunks")

    first = chunks[0]
    final = chunks[-1]
    require_chat_completion(first, expected_object="chat.completion.chunk")
    require(first["choices"][0]["delta"]["role"] == "assistant", "first chunk missing role")
    require(final["choices"][0]["finish_reason"] == "stop", "final chunk did not finish with stop")
    print(f"  ok: SSE stream for {image_id}")


def validate_history(client: Client, image_id: str) -> None:
    payload = validate_chat(client, image_id, "Can you build on the previous answer?")
    content = payload["choices"][0]["message"]["content"]
    require("prior user turn" in content, "history was not reflected in follow-up response")
    print(f"  ok: history persisted for {image_id}")


def require_chat_completion(payload: Any, *, expected_object: str) -> None:
    require(isinstance(payload, dict), f"{expected_object} payload was not an object")
    require(payload.get("object") == expected_object, f"expected object {expected_object}")
    require(str(payload.get("id", "")).startswith("chatcmpl-"), "completion id had wrong prefix")
    require(isinstance(payload.get("created"), int), "completion created was not an integer")
    require(isinstance(payload.get("model"), str) and payload["model"], "completion model missing")
    require(payload.get("service_tier") == "default", "completion service_tier missing")
    require(payload.get("system_fingerprint"), "completion system_fingerprint missing")

    choices = payload.get("choices")
    require(isinstance(choices, list) and choices, "completion choices missing")
    choice = choices[0]
    require(choice.get("index") == 0, "choice index missing")
    require("logprobs" in choice, "choice logprobs missing")

    if expected_object == "chat.completion":
        message = choice.get("message", {})
        usage = payload.get("usage", {})
        require(message.get("role") == "assistant", "chat message role missing")
        require("content" in message, "chat message content missing")
        require(message.get("annotations") == [], "chat message annotations should be an empty list")
        require("refusal" in message, "chat message refusal field missing")
        require(choice.get("finish_reason") == "stop", "chat finish_reason should be stop")
        require(usage.get("total_tokens") == usage.get("prompt_tokens") + usage.get("completion_tokens"),
                "usage token totals were inconsistent")
        require("prompt_tokens_details" in usage, "prompt token details missing")
        require("completion_tokens_details" in usage, "completion token details missing")
    else:
        require("delta" in choice, "stream chunk delta missing")
        require("usage" in payload, "stream chunk usage field missing")


def parse_sse_data_events(text: str) -> list[str]:
    events: list[str] = []

    for frame in text.split("\n\n"):
        for line in frame.splitlines():
            if line.startswith("data: "):
                events.append(line[len("data: ") :])

    return events


def decode_json(body: bytes) -> dict[str, Any]:
    try:
        payload = json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise AssertionError(f"response was not JSON: {body[:300]!r}") from error

    require(isinstance(payload, dict), "JSON response was not an object")
    return payload


def require_header_contains(headers: dict[str, str], name: str, expected: str) -> None:
    value = next((value for key, value in headers.items() if key.lower() == name), "")
    require(expected in value, f"expected {name} to contain {expected!r}, got {value!r}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, ApiError) as error:
        print(f"API smoke test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
