defmodule Inkit.VisualAssistant.Workflows do
  @moduledoc false

  require Ash.Query
  require Logger

  alias Inkit.Cache
  alias Inkit.Repo

  alias Inkit.VisualAssistant.{
    ApiLog,
    FileStorage,
    Message,
    MockAI,
    Retention,
    RetentionRun,
    RetentionSetting,
    UploadedImage
  }

  def create_image_from_upload(path, original_filename, content_type \\ nil) do
    with {:ok, attrs} <- FileStorage.validate_and_store(path, original_filename, content_type),
         attrs <- Map.put(attrs, :public_id, unique_id()),
         {:ok, image} <- create_image(attrs) do
      analysis = MockAI.vision_analysis(image)
      Cache.put({:analysis, image.public_id}, analysis)
      {:ok, image, analysis}
    end
  end

  def get_image(public_id) do
    cache_key = {:image, public_id}

    case Cache.get(cache_key) do
      {:ok, image} ->
        if image_file_available?(image) do
          {:ok, image}
        else
          Cache.delete(cache_key)
          cleanup_missing_image(image)
          {:error, :storage_missing}
        end

      :miss ->
        read_image(public_id, cache_key)
    end
  end

  def list_messages(public_id) do
    with {:ok, image} <- get_image(public_id) do
      {:ok, messages_for_image(image.id)}
    end
  end

  def list_messages_for_images([]), do: {:ok, %{}}

  def list_messages_for_images(images) do
    image_ids = Enum.map(images, & &1.id)

    Message
    |> Ash.Query.for_read(:read)
    |> Ash.Query.filter(uploaded_image_id in ^image_ids)
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.read()
    |> case do
      {:ok, messages} -> {:ok, Enum.group_by(messages, & &1.uploaded_image_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_conversation(public_id) do
    with {:ok, image} <- get_image(public_id) do
      analysis =
        case Cache.get({:analysis, image.public_id}) do
          {:ok, cached} -> cached
          :miss -> MockAI.vision_analysis(image)
        end

      {:ok, image, analysis, messages_for_image(image.id)}
    end
  end

  def list_recent_images(limit \\ 8) do
    UploadedImage
    |> Ash.Query.for_read(:read)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read()
  end

  def list_api_logs(limit \\ 50) do
    ApiLog
    |> Ash.Query.for_read(:read)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read()
  end

  def list_api_logs_page(page, page_size \\ 25) do
    page = max(page, 1)
    page_size = max(page_size, 1)

    logs =
      ApiLog
      |> Ash.Query.for_read(:read)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(page_size)
      |> Ash.Query.offset((page - 1) * page_size)
      |> Ash.read()

    with {:ok, logs} <- logs,
         {:ok, total} <- count_api_logs() do
      {:ok, logs, total}
    end
  end

  def list_api_logs_for_image(public_id, limit \\ 10) do
    ApiLog
    |> Ash.Query.for_read(:read)
    |> Ash.Query.filter(image_public_id == ^public_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read()
  end

  def usage_summary do
    with {:ok, uploads} <- count_upload_logs(),
         {:ok, total} <- count_api_logs() do
      %{
        image_uploads: uploads,
        api_requests: total
      }
    else
      {:error, _reason} ->
        %{
          image_uploads: 0,
          api_requests: 0
        }
    end
  end

  def record_api_log(attrs) do
    ApiLog
    |> Ash.Changeset.for_create(:create, %{
      method: attrs.method,
      path: attrs.path,
      status: attrs.status,
      duration_ms: attrs.duration_ms,
      image_public_id: Map.get(attrs, :image_public_id)
    })
    |> Ash.create()
  end

  def record_api_log_async(attrs) do
    if Application.get_env(:inkit, :async_api_logs, true) do
      case start_api_log_task(attrs) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.warning("Could not start API log task: #{inspect(reason)}")
          :ok
      end
    else
      safe_record_api_log(attrs)
    end
  end

  defp start_api_log_task(attrs) do
    case Process.whereis(Inkit.TaskSupervisor) do
      nil ->
        Task.start(fn -> safe_record_api_log(attrs) end)

      _pid ->
        Task.Supervisor.start_child(Inkit.TaskSupervisor, fn -> safe_record_api_log(attrs) end)
    end
  catch
    :exit, reason -> {:error, reason}
  end

  def chat(public_id, prompt) do
    with :ok <- validate_prompt(prompt),
         {:ok, image} <- get_image(public_id) do
      history = messages_for_image(image.id)
      response = MockAI.chat(image, prompt, history)
      assistant_content = MockAI.content_from_response(response)

      persist_exchange(image, prompt, assistant_content, response["id"], response)
    end
  end

  def prepare_stream(public_id, prompt) do
    # Mock streaming is pseudo-streaming: the full deterministic response is
    # built first, then LiveView dribbles these chunks with Process.send_after/3.
    # A real provider integration should replace this boundary with provider
    # streaming instead of assuming these chunks are generated incrementally.
    with :ok <- validate_prompt(prompt),
         {:ok, image} <- get_image(public_id) do
      history = messages_for_image(image.id)
      {response, chunks} = MockAI.stream_chunks(image, prompt, history)

      {:ok,
       %{
         image: image,
         prompt: prompt,
         response: response,
         chunks: chunks,
         assistant_content: MockAI.content_from_response(response)
       }}
    end
  end

  def persist_stream(%{
        image: image,
        prompt: prompt,
        response: response,
        assistant_content: assistant_content
      }) do
    case persist_exchange(image, prompt, assistant_content, response["id"], :ok) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def image_view(%UploadedImage{} = image) do
    %{
      id: image.public_id,
      original_filename: image.original_filename,
      label: image.label,
      content_type: image.content_type,
      size: image.size,
      inserted_at: image.inserted_at
    }
  end

  def update_image_label(public_id, label) do
    with {:ok, image} <- get_image(public_id),
         {:ok, image} <-
           image
           |> Ash.Changeset.for_update(:update_label, %{label: normalized_label(label)})
           |> Ash.update() do
      Cache.put({:image, image.public_id}, image)
      {:ok, image}
    end
  end

  def delete_image(public_id) do
    with {:ok, image} <- get_image(public_id) do
      transaction_ok(fn ->
        delete_messages(image)
        delete_image_record(image)
      end)
    end
  end

  def clear_all do
    transaction_ok(fn ->
      with :ok <-
             UploadedImage
             |> Ash.Query.for_read(:read)
             |> Ash.read!()
             |> delete_all_images() do
        Cache.clear()
        :ok
      end
    end)
  end

  def retention_settings do
    case RetentionSetting.fetch() do
      {:ok, setting} -> {:ok, setting}
      {:error, _} = err -> err
    end
  end

  def update_retention_settings(attrs) do
    RetentionSetting.update(attrs)
  end

  def list_retention_runs(limit \\ 20) do
    RetentionRun
    |> Ash.Query.for_read(:read)
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read()
  end

  def run_retention_now do
    Retention.run_now(triggered_by: :manual)
  end

  def clear_api_logs do
    transaction_ok(fn ->
      ApiLog
      |> Ash.Query.for_read(:read)
      |> Ash.read!()
      |> Enum.each(&Ash.destroy!/1)

      :ok
    end)
  end

  defp create_image(attrs) do
    UploadedImage
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  defp read_image(public_id, cache_key) do
    UploadedImage
    |> Ash.Query.for_read(:by_public_id, %{public_id: public_id})
    |> Ash.read_one()
    |> case do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, image} ->
        if image_file_available?(image) do
          Cache.put(cache_key, image)
          {:ok, image}
        else
          cleanup_missing_image(image)
          {:error, :storage_missing}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp image_file_available?(%UploadedImage{storage_path: storage_path})
       when is_binary(storage_path),
       do: File.exists?(storage_path)

  defp image_file_available?(_image), do: false

  defp cleanup_missing_image(image) do
    Logger.warning("Cleaning up image #{image.public_id}: storage file is missing")

    case transaction_ok(fn ->
           delete_messages(image)
           delete_image_record(image)
         end) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Could not clean up missing image: #{inspect(reason)}")
    end
  end

  defp create_message(image, role, content, response_id \\ nil) do
    Message
    |> Ash.Changeset.for_create(:create, %{
      uploaded_image_id: image.id,
      role: role,
      content: String.trim(content),
      response_id: response_id
    })
    |> Ash.create()
  end

  defp persist_exchange(image, prompt, assistant_content, response_id, return_value) do
    transaction_value(fn ->
      with {:ok, _user} <- create_message(image, "user", prompt),
           {:ok, _assistant} <- create_message(image, "assistant", assistant_content, response_id) do
        return_value
      end
    end)
  end

  defp messages_for_image(image_id) do
    Message
    |> Ash.Query.for_read(:for_image, %{uploaded_image_id: image_id})
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.read!()
  end

  defp delete_messages(image) do
    image.id
    |> messages_for_image()
    |> Enum.each(&Ash.destroy!/1)
  end

  defp delete_all_images(images) do
    Enum.reduce_while(images, :ok, fn image, :ok ->
      delete_messages(image)

      case delete_image_record(image) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_image_record(image) do
    with :ok <- delete_stored_file(image),
         :ok <- Ash.destroy(image) do
      Cache.delete({:image, image.public_id})
      Cache.delete({:analysis, image.public_id})
      :ok
    else
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_stored_file(image) do
    case File.rm(image.storage_path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} when reason in [:erofs, :eacces] ->
        if String.starts_with?(image.storage_path, "/app/demo/uploads/") do
          Logger.warning("Skipping delete for read-only demo upload #{image.storage_path}")
          :ok
        else
          Logger.warning("Could not delete #{image.storage_path}: #{inspect(reason)}")
          {:error, {:file_delete_failed, reason}}
        end

      {:error, reason} ->
        Logger.warning("Could not delete #{image.storage_path}: #{inspect(reason)}")
        {:error, {:file_delete_failed, reason}}
    end
  end

  defp transaction_value(fun) do
    case Repo.transaction(fn -> rollback_on_error(fun.()) end) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp transaction_ok(fun) do
    case Repo.transaction(fn -> rollback_on_error(fun.()) end) do
      {:ok, :ok} -> :ok
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rollback_on_error({:error, reason}), do: Repo.rollback(reason)
  defp rollback_on_error(value), do: value

  defp validate_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      {:error, :empty_prompt}
    else
      :ok
    end
  end

  defp validate_prompt(_prompt), do: {:error, :empty_prompt}

  defp normalized_label(label) do
    label
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      value -> String.slice(value, 0, 80)
    end
  end

  defp count_api_logs do
    ApiLog
    |> Ash.Query.for_read(:read)
    |> Ash.count()
  end

  defp count_upload_logs do
    paths = ["/upload", "/live/upload"]

    ApiLog
    |> Ash.Query.for_read(:read)
    |> Ash.Query.filter(path in ^paths and status >= 200 and status <= 299)
    |> Ash.count()
  end

  defp safe_record_api_log(attrs) do
    case record_api_log(attrs) do
      {:ok, _log} -> :ok
      {:error, reason} -> Logger.warning("Could not record API log: #{inspect(reason)}")
    end
  catch
    :exit, reason -> Logger.warning("Could not record API log: #{inspect(reason)}")
  end

  defp unique_id do
    "img_#{10 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)}"
  end
end
