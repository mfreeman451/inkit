defmodule Inkit.VisualAssistant.RetentionTest do
  use InkitWeb.ConnCase, async: false

  require Ash.Query

  alias Ecto.Adapters.SQL, as: EctoSQL
  alias Inkit.ImageFixture
  alias Inkit.VisualAssistant.{ApiLog, Message, Retention, UploadedImage, Workflows}
  alias Inkit.VisualAssistant.RetentionSetting

  test "purges messages older than the cutoff and keeps fresh ones" do
    upload = ImageFixture.png_upload()

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    {:ok, _response} = Workflows.chat(image.public_id, "old")
    {:ok, _response} = Workflows.chat(image.public_id, "fresh")

    old_message = find_oldest_message(image)
    backdate!("conversation_messages", old_message.id, -10)

    {:ok, run} = Retention.run_now(messages_days: 5, api_logs_days: 365, images_days: 365)

    assert run.messages_deleted >= 1
    assert run.status == :ok
    assert run.triggered_by == :manual
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

    {:ok, run} = Retention.run_now(messages_days: 365, api_logs_days: 10, images_days: 365)

    assert run.api_logs_deleted >= 1
    refute Enum.member?(ids(ApiLog), old_log.id)
  end

  test "purges orphaned images older than the cutoff" do
    upload = ImageFixture.png_upload()

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    backdate!("uploaded_images", image.id, -60)

    {:ok, run} = Retention.run_now(messages_days: 365, api_logs_days: 365, images_days: 30)

    assert run.images_deleted >= 1
    refute Enum.member?(ids(UploadedImage), image.id)
  end

  test "records sweeps as RetentionRun rows" do
    {:ok, _run} = Retention.run_now(messages_days: 365, api_logs_days: 365, images_days: 365)

    {:ok, runs} = Workflows.list_retention_runs(5)
    assert runs != []
    assert [latest | _] = runs
    assert latest.status == :ok
    assert latest.triggered_by == :manual
    assert is_integer(latest.duration_ms)
  end

  test "settings singleton is read + update" do
    {:ok, original} = RetentionSetting.fetch()

    {:ok, updated} = RetentionSetting.update(%{messages_days: original.messages_days + 1})
    assert updated.messages_days == original.messages_days + 1

    {:ok, reread} = RetentionSetting.fetch()
    assert reread.messages_days == updated.messages_days
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
