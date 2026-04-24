defmodule Inkit.VisualAssistant.RetentionTest do
  use InkitWeb.ConnCase, async: false

  require Ash.Query

  alias Ecto.Adapters.SQL, as: EctoSQL
  alias Inkit.ImageFixture
  alias Inkit.VisualAssistant.{ApiLog, Message, Retention, UploadedImage, Workflows}

  test "purges messages older than the cutoff and keeps fresh ones" do
    upload = ImageFixture.png_upload()

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    {:ok, _response} = Workflows.chat(image.public_id, "old")
    {:ok, _response} = Workflows.chat(image.public_id, "fresh")

    old_message = find_oldest_message(image)
    backdate!("conversation_messages", old_message.id, -10)

    counts = Retention.run_now(messages_days: 5, api_logs_days: 365, images_days: 365)

    assert counts.messages >= 1
    refute Enum.member?(ids(Message), old_message.id)
  end

  test "purges api logs older than the cutoff" do
    {:ok, old_log} =
      Workflows.record_api_log(%{
        method: "GET",
        path: "/upload",
        status: 200,
        duration_ms: 1
      })

    {:ok, _fresh_log} =
      Workflows.record_api_log(%{
        method: "GET",
        path: "/upload",
        status: 200,
        duration_ms: 1
      })

    backdate!("api_logs", old_log.id, -20)

    counts = Retention.run_now(messages_days: 365, api_logs_days: 10, images_days: 365)

    assert counts.api_logs >= 1
    refute Enum.member?(ids(ApiLog), old_log.id)
  end

  test "purges orphaned images older than the cutoff" do
    upload = ImageFixture.png_upload()

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    backdate!("uploaded_images", image.id, -60)

    counts = Retention.run_now(messages_days: 365, api_logs_days: 365, images_days: 30)

    assert counts.images >= 1
    refute Enum.member?(ids(UploadedImage), image.id)
  end

  defp find_oldest_message(image) do
    Message
    |> Ash.Query.for_read(:for_image, %{uploaded_image_id: image.id})
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.read!()
    |> List.first()
  end

  defp backdate!(table, id, days) do
    new_time = DateTime.add(DateTime.utc_now(), days * 86_400, :second)

    EctoSQL.query!(
      Inkit.Repo,
      "UPDATE #{table} SET inserted_at = ? WHERE id = ?",
      [DateTime.to_iso8601(new_time), id]
    )

    :ok
  end

  defp ids(resource) do
    resource
    |> Ash.Query.for_read(:read)
    |> Ash.read!()
    |> Enum.map(& &1.id)
  end
end
