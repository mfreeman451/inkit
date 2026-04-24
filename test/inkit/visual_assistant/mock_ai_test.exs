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

    assert response["id"] =~ "chatcmpl_"
    assert response["object"] == "chat.completion"
    assert [%{"message" => %{"role" => "assistant"}}] = response["choices"]
    assert response["usage"]["total_tokens"] >= response["usage"]["completion_tokens"]
  end
end
