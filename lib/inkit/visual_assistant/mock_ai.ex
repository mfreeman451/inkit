defmodule Inkit.VisualAssistant.MockAI do
  @moduledoc false

  alias Inkit.VisualAssistant.UploadedImage

  @model "mock-gpt-4o-mini"
  @vision_model "mock-gpt-4o-mini-vision"
  @system_fingerprint "fp_mock_visual_assistant"

  def vision_analysis(%UploadedImage{} = image) do
    content = mock_scene_analysis(image)

    chat_completion(@vision_model, content,
      prompt_tokens: 128,
      completion_tokens: token_count(content),
      seed: {image.id, :vision}
    )
  end

  def chat(%UploadedImage{} = image, prompt, history) do
    prior_user_messages = Enum.count(history, &(&1.role == "user"))
    content = mock_chat_answer(image, prompt, history)

    chat_completion(@model, content,
      prompt_tokens: token_count(prompt) + token_count(history),
      completion_tokens: token_count(content),
      seed: {image.id, prompt, prior_user_messages}
    )
  end

  def stream_chunks(%UploadedImage{} = image, prompt, history) do
    response = chat(image, prompt, history)
    id = response["id"]
    created = response["created"]
    content = response |> get_in(["choices", Access.at(0), "message", "content"])

    start = %{
      "id" => id,
      "object" => "chat.completion.chunk",
      "created" => created,
      "model" => @model,
      "system_fingerprint" => @system_fingerprint,
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

    chunks =
      content
      |> chunk_content()
      |> Enum.map(fn token ->
        %{
          "id" => id,
          "object" => "chat.completion.chunk",
          "created" => created,
          "model" => @model,
          "system_fingerprint" => @system_fingerprint,
          "service_tier" => "default",
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{"content" => token},
              "logprobs" => nil,
              "finish_reason" => nil
            }
          ],
          "usage" => nil
        }
      end)

    finish = %{
      "id" => id,
      "object" => "chat.completion.chunk",
      "created" => created,
      "model" => @model,
      "system_fingerprint" => @system_fingerprint,
      "service_tier" => "default",
      "choices" => [
        %{"index" => 0, "delta" => %{}, "logprobs" => nil, "finish_reason" => "stop"}
      ],
      "usage" => nil
    }

    {response, [start | chunks] ++ [finish]}
  end

  def content_from_response(response) do
    get_in(response, ["choices", Access.at(0), "message", "content"])
  end

  defp mock_scene_analysis(image) do
    cond do
      kitchen_image?(image) ->
        """
        This looks like a bright contemporary kitchen concept with a clean white perimeter, a central island, warm wood accents, and black metal lighting for contrast.

        Key design read:
        - Style: modern farmhouse with transitional cabinet detailing.
        - Cabinetry: painted shaker-style fronts, likely satin white.
        - Counters: light stone or quartz with subtle gray movement.
        - Backsplash: simple white tile that keeps the wall quiet.
        - Mood: polished, approachable, and practical for a family kitchen.

        Because this is the mock provider, the response is deterministic and based on the demo image metadata rather than a real vision model.
        """

      bathroom_image?(image) ->
        """
        This looks like a contemporary bathroom renovation with large-format marble-look tile, a frameless glass shower, a sculptural freestanding tub, and matte black fixtures for contrast.

        Key design read:
        - Style: contemporary spa bath with a high-contrast black and white palette.
        - Tile: marble-look porcelain or stone slab effect across the shower walls and floor.
        - Fixtures: matte black faucets, shower hardware, and mirror framing.
        - Lighting: recessed ceiling lights plus an illuminated shower niche.
        - Mood: clean, upscale, and architectural without feeling overly decorative.

        Because this is the mock provider, the response is deterministic and based on the demo image metadata rather than a real vision model.
        """

      true ->
        """
        The mock vision provider received #{image.original_filename} (#{image.content_type}, #{image.size} bytes) and created a structured placeholder analysis.

        Likely review dimensions:
        - Overall subject and composition.
        - Visible materials, finishes, and color palette.
        - Functional or design questions worth asking next.
        - Any constraints implied by the uploaded image.

        Connect an OpenAI key later to replace this deterministic mock with real image understanding.
        """
    end
    |> String.trim()
  end

  defp mock_chat_answer(image, prompt, history) do
    prompt = String.trim(prompt)
    normalized = String.downcase(prompt)
    prior_user_messages = Enum.count(history, &(&1.role == "user"))
    memory_note = memory_note(prior_user_messages, last_user_message(history))

    answer =
      cond do
        kitchen_image?(image) -> kitchen_chat_answer(normalized)
        bathroom_image?(image) -> bathroom_chat_answer(normalized)
        true -> generic_chat_answer(image, prompt)
      end

    [String.trim(answer), memory_note]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp last_user_message(history) do
    history
    |> Enum.reverse()
    |> Enum.find(&(&1.role == "user"))
    |> case do
      nil -> nil
      message -> message.content
    end
  end

  defp kitchen_chat_answer(normalized) do
    cond do
      String.contains?(normalized, ["style", "material", "cabinet", "counter", "backsplash"]) ->
        """
        The style is closest to modern farmhouse with a transitional polish. The cabinets look like white painted shaker fronts, the countertop reads as quartz or marble-look stone, and the backsplash appears to be a simple white tile. The black pendants and stools create the strongest contrast, while the wood shelving warms up the room.
        """

      String.contains?(normalized, ["what", "going on", "notice"]) ->
        """
        This appears to be a staged kitchen renovation image. The space is organized around a large island, with white shaker cabinetry, a light stone countertop, warm open shelving, and black pendant lights adding contrast over the work surface.

        The overall direction reads contemporary farmhouse: bright, practical, and intentionally neutral, with enough black hardware and wood texture to keep it from feeling sterile.
        """

      String.contains?(normalized, ["improve", "change", "recommend"]) ->
        """
        I would keep the clean cabinet and counter palette, then add depth through texture: a runner with muted color, warmer under-cabinet lighting, and a few darker accessories near the open shelves. If this were a real remodel review, I would also check traffic clearance around the island and whether the pendant scale matches the island length.
        """

      true ->
        """
        This kitchen reads as a bright contemporary farmhouse renovation with white cabinetry, warm wood accents, black fixtures, and a large island anchoring the layout.
        """
    end
  end

  defp bathroom_chat_answer(normalized) do
    cond do
      String.contains?(normalized, ["style", "material", "tile", "fixture"]) ->
        """
        The style is contemporary luxury bath. The dominant material appears to be marble-look porcelain or slab-style stone, paired with matte black fixtures, glass shower panels, a white freestanding tub, and a dark vanity base. The illuminated shower niche is the strongest feature detail.
        """

      String.contains?(normalized, ["what", "going on", "notice"]) ->
        """
        This appears to be a polished bathroom renovation image. The main features are a freestanding tub, a glass-enclosed shower, marble-look surfaces, black plumbing fixtures, and a broad vanity counter with a strong black-framed mirror.

        The room reads like a contemporary spa bath: minimal ornament, bright surfaces, and black accents used to define the edges of the fixtures and glass.
        """

      String.contains?(normalized, ["improve", "change", "recommend"]) ->
        """
        I would preserve the black and white palette, then soften the space with towels, a bath mat, and one warm wood or woven accent. If this were a real project review, I would also check shower glass clearance, tub access, and whether the vanity lighting is flattering enough at face height.
        """

      true ->
        """
        This bathroom reads as a contemporary spa bath with marble-look tile, a frameless shower, a freestanding tub, and matte black fixtures.
        """
    end
  end

  defp generic_chat_answer(image, prompt) do
    """
    For #{image.original_filename}, I would answer "#{prompt}" by grounding the response in the uploaded image, then separating visible observations from design recommendations. In mock mode I cannot inspect pixels, so this response stays deterministic while still preserving the same conversation flow and persistence behavior as a real provider.
    """
  end

  defp kitchen_image?(image) do
    image.original_filename
    |> String.downcase()
    |> String.contains?(["kitchen", "cabinet", "interior", "renovation"])
  end

  defp bathroom_image?(image) do
    image.original_filename
    |> String.downcase()
    |> String.contains?(["bathroom", "bath", "shower", "tub", "vanity"])
  end

  defp memory_note(0, _last), do: ""

  defp memory_note(count, nil) do
    "I also have #{count} prior user turn#{plural(count)} saved for this image, so follow-up questions can build on the conversation instead of starting over."
  end

  defp memory_note(count, last_user_message) do
    snippet = last_user_message |> String.trim() |> String.slice(0, 160)

    "Building on our previous exchange — you last asked: \"#{snippet}\". " <>
      "I have #{count} prior user turn#{plural(count)} saved for this image, " <>
      "so this follow-up stays grounded in that history."
  end

  defp chat_completion(model, content, usage) do
    prompt_tokens = Keyword.fetch!(usage, :prompt_tokens)
    completion_tokens = Keyword.fetch!(usage, :completion_tokens)
    seed = Keyword.fetch!(usage, :seed)

    %{
      "id" => "chatcmpl-#{stable_id(seed)}",
      "object" => "chat.completion",
      "created" => System.system_time(:second),
      "model" => model,
      "system_fingerprint" => @system_fingerprint,
      "service_tier" => "default",
      "choices" => [
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
      ],
      "usage" => %{
        "prompt_tokens" => prompt_tokens,
        "completion_tokens" => completion_tokens,
        "total_tokens" => prompt_tokens + completion_tokens,
        "prompt_tokens_details" => %{
          "audio_tokens" => 0,
          "cached_tokens" => 0
        },
        "completion_tokens_details" => %{
          "accepted_prediction_tokens" => 0,
          "audio_tokens" => 0,
          "reasoning_tokens" => 0,
          "rejected_prediction_tokens" => 0
        }
      }
    }
  end

  defp chunk_content(content) do
    content
    |> String.split(~r/(\s+)/, include_captures: true, trim: true)
    |> Enum.chunk_every(4)
    |> Enum.map(&Enum.join/1)
  end

  defp token_count(messages) when is_list(messages) do
    messages
    |> Enum.map_join(" ", & &1.content)
    |> token_count()
  end

  defp token_count(text) do
    text
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> length()
    |> max(1)
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"

  defp stable_id(seed) do
    seed
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 22)
  end
end
