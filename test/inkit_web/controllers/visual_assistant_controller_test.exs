defmodule InkitWeb.VisualAssistantControllerTest do
  use InkitWeb.ConnCase

  alias Inkit.ImageFixture

  test "POST /upload stores an image and returns mock analysis", %{conn: conn} do
    conn = post(conn, ~p"/upload", %{"image" => ImageFixture.png_upload()})

    assert %{
             "image" => %{"id" => image_id, "content_type" => "image/png"} = image,
             "analysis" => %{"object" => "chat.completion"}
           } = json_response(conn, 201)

    assert String.starts_with?(image_id, "img_")
    refute Map.has_key?(image, "sha256")
  end

  test "POST /upload rejects unsupported files", %{conn: conn} do
    path = Path.join(System.tmp_dir!(), "inkit-test-#{System.unique_integer([:positive])}.txt")
    File.write!(path, "not an image")

    upload = %Plug.Upload{path: path, filename: "bad.txt", content_type: "text/plain"}
    conn = post(conn, ~p"/upload", %{"image" => upload})

    assert %{"error" => %{"code" => "unsupported_media_type"}} = json_response(conn, 415)
  end

  test "GET /images/:image_id renders a validated upload", %{conn: conn} do
    image_id =
      conn
      |> post(~p"/upload", %{"image" => ImageFixture.png_upload()})
      |> json_response(201)
      |> get_in(["image", "id"])

    conn = conn |> recycle() |> get(~p"/images/#{image_id}")

    assert response(conn, 200) =~ <<0x89, "PNG">>
    assert ["image/png" <> _] = get_resp_header(conn, "content-type")
  end

  test "POST /chat/:image_id answers a question about an uploaded image", %{conn: conn} do
    image_id =
      conn
      |> post(~p"/upload", %{"image" => ImageFixture.png_upload()})
      |> json_response(201)
      |> get_in(["image", "id"])

    conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/#{image_id}", Jason.encode!(%{question: "What do you notice?"}))

    assert %{
             "object" => "chat.completion",
             "service_tier" => "default",
             "system_fingerprint" => "fp_mock_visual_assistant",
             "choices" => [
               %{
                 "message" => %{
                   "role" => "assistant",
                   "content" => content,
                   "refusal" => nil,
                   "annotations" => []
                 },
                 "logprobs" => nil,
                 "finish_reason" => "stop"
               }
             ],
             "usage" => %{
               "prompt_tokens" => prompt_tokens,
               "completion_tokens" => completion_tokens,
               "total_tokens" => total_tokens,
               "prompt_tokens_details" => %{"cached_tokens" => 0},
               "completion_tokens_details" => %{"reasoning_tokens" => 0}
             }
           } = json_response(conn, 200)

    assert total_tokens == prompt_tokens + completion_tokens
    assert content =~ "What do you notice?"
    assert content =~ "real provider"
  end

  test "POST /chat/:image_id/stream streams OpenAI-style SSE chunks and persists history", %{
    conn: conn
  } do
    image_id =
      conn
      |> post(~p"/upload", %{"image" => ImageFixture.png_upload("kitchen.png")})
      |> json_response(201)
      |> get_in(["image", "id"])

    conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/#{image_id}/stream", Jason.encode!(%{question: "What do you notice?"}))

    assert response = response(conn, 200)
    assert ["text/event-stream" <> _] = get_resp_header(conn, "content-type")
    assert response =~ "data: [DONE]\n\n"

    events = parse_sse_data_events(response)

    assert "[DONE]" == List.last(events)

    chunks =
      events
      |> Enum.reject(&(&1 == "[DONE]"))
      |> Enum.map(&Jason.decode!/1)

    assert [
             %{
               "id" => id,
               "object" => "chat.completion.chunk",
               "created" => created,
               "model" => "mock-gpt-4o-mini",
               "choices" => [
                 %{
                   "delta" => %{"role" => "assistant", "content" => "", "refusal" => nil},
                   "finish_reason" => nil,
                   "logprobs" => nil
                 }
               ],
               "usage" => nil
             }
             | _
           ] = chunks

    assert String.starts_with?(id, "chatcmpl-")
    assert is_integer(created)

    assert %{
             "id" => ^id,
             "object" => "chat.completion.chunk",
             "choices" => [
               %{
                 "delta" => %{},
                 "finish_reason" => "stop",
                 "logprobs" => nil
               }
             ],
             "usage" => nil
           } = List.last(chunks)

    conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/#{image_id}", Jason.encode!(%{question: "Follow up?"}))

    content = get_in(json_response(conn, 200), ["choices", Access.at(0), "message", "content"])
    assert content =~ "1 prior user turn saved"
  end

  test "POST /chat/:image_id returns not found for unknown images", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/img_missing", Jason.encode!(%{question: "Hello?"}))

    assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
  end

  test "POST /chat/:image_id/stream validates the prompt before opening SSE", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/img_missing/stream", Jason.encode!(%{question: ""}))

    assert %{"error" => %{"code" => "empty_prompt"}} = json_response(conn, 400)
  end

  test "SSE stream tags chunks with ascending `id:` lines", %{conn: conn} do
    image_id =
      conn
      |> post(~p"/upload", %{"image" => ImageFixture.png_upload("kitchen.png")})
      |> json_response(201)
      |> get_in(["image", "id"])

    conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/#{image_id}/stream", Jason.encode!(%{question: "What do you notice?"}))

    response = response(conn, 200)
    ids = parse_sse_ids(response)

    assert ids != []
    assert ids == Enum.to_list(0..(length(ids) - 1))
  end

  test "Last-Event-ID resumes the stream past the acknowledged index", %{conn: conn} do
    image_id =
      conn
      |> post(~p"/upload", %{"image" => ImageFixture.png_upload("kitchen.png")})
      |> json_response(201)
      |> get_in(["image", "id"])

    resume_from = 2

    resumed =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("last-event-id", Integer.to_string(resume_from))
      |> post(~p"/chat/#{image_id}/stream", Jason.encode!(%{question: "What do you notice?"}))
      |> response(200)

    resumed_ids = parse_sse_ids(resumed)

    assert resumed_ids != []
    assert List.first(resumed_ids) == resume_from + 1

    # ids should be a strictly ascending, contiguous integer sequence.
    assert resumed_ids ==
             Enum.to_list(List.first(resumed_ids)..List.last(resumed_ids))

    # Early chunks should never appear in a resumed stream.
    refute Enum.any?(resumed_ids, fn id -> id <= resume_from end)
  end

  test "rate limiter returns 429 after exceeding configured max", %{conn: conn} do
    prior = Application.get_env(:inkit, :rate_limit)

    Application.put_env(:inkit, :rate_limit,
      enabled: true,
      window_ms: 60_000,
      max_requests: 2
    )

    Inkit.RateLimiter.reset()

    on_exit(fn ->
      Application.put_env(:inkit, :rate_limit, prior)
      Inkit.RateLimiter.reset()
    end)

    conn
    |> post(~p"/upload", %{"image" => ImageFixture.png_upload()})
    |> response(201)

    conn
    |> recycle()
    |> post(~p"/upload", %{"image" => ImageFixture.png_upload()})
    |> response(201)

    over =
      conn
      |> recycle()
      |> post(~p"/upload", %{"image" => ImageFixture.png_upload()})

    assert %{"error" => %{"code" => "rate_limited"}} = json_response(over, 429)
    assert get_resp_header(over, "retry-after") != []
  end

  defp parse_sse_ids(response) do
    response
    |> String.split("\n\n", trim: true)
    |> Enum.flat_map(fn frame ->
      frame
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "id: "))
      |> Enum.map(&String.replace_prefix(&1, "id: ", ""))
      |> Enum.map(&String.to_integer/1)
    end)
  end

  defp parse_sse_data_events(response) do
    response
    |> String.split("\n\n", trim: true)
    |> Enum.flat_map(fn frame ->
      frame
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data: "))
      |> Enum.map(&String.replace_prefix(&1, "data: ", ""))
    end)
  end
end
