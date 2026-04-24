defmodule Inkit.VisualAssistant.MockAITest do
  use ExUnit.Case, async: true

  alias Inkit.VisualAssistant.MockAI
  alias Inkit.VisualAssistant.UploadedImage

  test "vision analysis uses OpenAI-style chat completion shape" do
    image = %UploadedImage{
      public_id: "img_test",
      original_filename: "sample.png",
      content_type: "image/png"
    }

    response = MockAI.vision_analysis(image)

    assert response["id"] =~ "chatcmpl-"
    assert response["object"] == "chat.completion"
    assert response["created"] |> is_integer()
    assert response["model"] == "mock-gpt-4o-mini-vision"
    assert response["service_tier"] == "default"
    assert response["system_fingerprint"] == "fp_mock_visual_assistant"

    assert [
             %{
               "index" => 0,
               "message" => %{
                 "role" => "assistant",
                 "content" => content,
                 "refusal" => nil,
                 "annotations" => []
               },
               "logprobs" => nil,
               "finish_reason" => "stop"
             }
           ] = response["choices"]

    assert is_binary(content)
    assert response["usage"]["total_tokens"] >= response["usage"]["completion_tokens"]
    assert response["usage"]["prompt_tokens_details"]["cached_tokens"] == 0
    assert response["usage"]["completion_tokens_details"]["reasoning_tokens"] == 0
  end

  test "stream chunks use OpenAI chat completion chunk shape" do
    image = %UploadedImage{
      public_id: "img_test",
      original_filename: "sample.png",
      content_type: "image/png"
    }

    {_response, chunks} = MockAI.stream_chunks(image, "What do you notice?", [])

    assert [
             %{
               "id" => id,
               "object" => "chat.completion.chunk",
               "created" => created,
               "model" => "mock-gpt-4o-mini",
               "system_fingerprint" => "fp_mock_visual_assistant",
               "service_tier" => "default",
               "choices" => [
                 %{
                   "index" => 0,
                   "delta" => %{"role" => "assistant", "content" => "", "refusal" => nil},
                   "logprobs" => nil,
                   "finish_reason" => nil
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
                 "index" => 0,
                 "delta" => %{},
                 "logprobs" => nil,
                 "finish_reason" => "stop"
               }
             ],
             "usage" => nil
           } = List.last(chunks)
  end
end
