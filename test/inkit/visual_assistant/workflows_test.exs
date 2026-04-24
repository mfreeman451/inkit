defmodule Inkit.VisualAssistant.WorkflowsTest do
  use Inkit.DataCase

  alias Inkit.ImageFixture
  alias Inkit.VisualAssistant.Workflows

  test "creates an uploaded image with mock analysis" do
    upload = ImageFixture.png_upload()

    assert {:ok, image, analysis} =
             Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    assert image.public_id =~ "img_"
    assert image.content_type == "image/png"
    assert get_in(analysis, ["choices", Access.at(0), "message", "content"]) =~ upload.filename
  end

  test "prepares streaming chunks and persists per-image chat history" do
    upload = ImageFixture.png_upload()

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    assert {:ok, stream} = Workflows.prepare_stream(image.public_id, "Describe it")
    assert [%{"choices" => [%{"delta" => %{"role" => "assistant"}}]} | _] = stream.chunks
    assert List.last(stream.chunks)["choices"] |> hd() |> Map.fetch!("finish_reason") == "stop"
    assert :ok = Workflows.persist_stream(stream)

    assert {:ok, messages} = Workflows.list_messages(image.public_id)
    assert Enum.map(messages, & &1.role) == ["user", "assistant"]
    assert hd(messages).content == "Describe it"
  end

  test "answers a non-streaming question and persists history" do
    upload = ImageFixture.png_upload()

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    assert {:ok, response} = Workflows.chat(image.public_id, "What is in this image?")
    assert get_in(response, ["choices", Access.at(0), "message", "role"]) == "assistant"

    assert {:ok, messages} = Workflows.list_messages(image.public_id)
    assert Enum.map(messages, & &1.role) == ["user", "assistant"]
    assert hd(messages).content == "What is in this image?"
  end

  test "updates image labels" do
    upload = ImageFixture.png_upload()

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    assert {:ok, updated} = Workflows.update_image_label(image.public_id, "  Mood board  ")
    assert updated.label == "Mood board"

    assert {:ok, cleared} = Workflows.update_image_label(image.public_id, " ")
    assert cleared.label == nil
  end

  test "deletes one image and its messages" do
    upload = ImageFixture.png_upload()

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    assert {:ok, _response} = Workflows.chat(image.public_id, "What is in this image?")
    assert {:ok, :ok} = Workflows.delete_image(image.public_id)
    assert {:error, :not_found} = Workflows.get_image(image.public_id)
    refute File.exists?(image.storage_path)
  end

  test "clears all image and conversation data" do
    first = ImageFixture.png_upload()
    second = ImageFixture.png_upload()

    {:ok, first_image, _analysis} =
      Workflows.create_image_from_upload(first.path, first.filename, first.content_type)

    {:ok, second_image, _analysis} =
      Workflows.create_image_from_upload(second.path, second.filename, second.content_type)

    assert {:ok, _response} = Workflows.chat(first_image.public_id, "First?")
    assert {:ok, :ok} = Workflows.clear_all()
    assert {:ok, []} = Workflows.list_recent_images()
    assert {:error, :not_found} = Workflows.get_image(first_image.public_id)
    assert {:error, :not_found} = Workflows.get_image(second_image.public_id)
  end
end
