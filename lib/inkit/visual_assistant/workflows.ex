defmodule Inkit.VisualAssistant.Workflows do
  @moduledoc false

  require Ash.Query

  alias Inkit.Cache
  alias Inkit.Repo
  alias Inkit.VisualAssistant.{ApiLog, FileStorage, Message, MockAI, UploadedImage}

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
          {:error, :not_found}
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
         {:ok, all_logs} <- list_api_logs(10_000) do
      {:ok, logs, length(all_logs)}
    end
  end

  def usage_summary do
    case list_api_logs(10_000) do
      {:ok, logs} ->
        %{
          image_uploads: Enum.count(logs, &upload_log?/1),
          api_requests: length(logs)
        }

      {:error, _reason} ->
        %{image_uploads: 0, api_requests: 0}
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
      sha256: image.sha256,
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
      transaction(fn ->
        delete_messages(image)
        delete_image_record(image)
      end)
    end
  end

  def clear_all do
    transaction(fn ->
      UploadedImage
      |> Ash.Query.for_read(:read)
      |> Ash.read!()
      |> Enum.each(fn image ->
        image.id
        |> messages_for_image()
        |> Enum.each(&Ash.destroy!/1)

        Ash.destroy!(image)
        File.rm(image.storage_path)
      end)

      Cache.clear()
      :ok
    end)
  end

  def clear_api_logs do
    transaction(fn ->
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
          {:error, :not_found}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp image_file_available?(%UploadedImage{storage_path: storage_path})
       when is_binary(storage_path),
       do: File.exists?(storage_path)

  defp image_file_available?(_image), do: false

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
    transaction(fn ->
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

  defp delete_image_record(image) do
    case Ash.destroy(image) do
      :ok ->
        File.rm(image.storage_path)
        Cache.delete({:image, image.public_id})
        Cache.delete({:analysis, image.public_id})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transaction(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        value -> value
      end
    end)
  end

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

  defp upload_log?(%{path: path, status: status}) do
    path in ["/upload", "/live/upload"] and status in 200..299
  end

  defp unique_id do
    "img_#{10 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)}"
  end
end
