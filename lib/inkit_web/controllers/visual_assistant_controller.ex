defmodule InkitWeb.VisualAssistantController do
  use InkitWeb, :controller

  require Logger

  alias Inkit.VisualAssistant.Workflows, as: VisualAssistant

  def upload(conn, params) do
    with {:ok, upload} <- fetch_upload(params),
         {:ok, image, analysis} <-
           VisualAssistant.create_image_from_upload(
             upload.path,
             upload.filename,
             upload.content_type
           ) do
      conn
      |> put_status(:created)
      |> json(%{image: VisualAssistant.image_view(image), analysis: analysis})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def image(conn, %{"image_id" => image_id}) do
    case VisualAssistant.get_image(image_id) do
      {:ok, image} ->
        conn
        |> put_resp_content_type(image.content_type)
        |> send_file(200, image.storage_path)

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def chat(conn, %{"image_id" => image_id} = params) do
    prompt = prompt_param(params)

    case VisualAssistant.chat(image_id, prompt) do
      {:ok, response} -> json(conn, response)
      {:error, reason} -> error(conn, reason)
    end
  end

  def stream_chat(conn, %{"image_id" => image_id} = params) do
    prompt = prompt_param(params)

    case VisualAssistant.prepare_stream(image_id, prompt) do
      {:ok, stream} -> stream_sse(conn, stream)
      {:error, reason} -> error(conn, reason)
    end
  end

  defp fetch_upload(%{"image" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp fetch_upload(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp fetch_upload(_params), do: {:error, :missing_file}

  defp prompt_param(params) do
    params["prompt"] || params["question"] || params["message"] || ""
  end

  defp error(conn, reason) do
    {status, code, message} = error_details(reason)

    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end

  defp stream_sse(conn, stream) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(:ok)

    case write_stream_chunks(conn, stream.chunks) do
      {:ok, conn} ->
        case VisualAssistant.persist_stream(stream) do
          :ok ->
            write_sse_done(conn)

          {:error, reason} ->
            Logger.warning("Could not persist streamed chat: #{inspect(reason)}")
            write_sse_error(conn, reason)
        end

      {:error, reason, conn} ->
        Logger.warning("SSE chat stream stopped before completion: #{inspect(reason)}")
        conn
    end
  end

  defp write_stream_chunks(conn, chunks) do
    Enum.reduce_while(chunks, {:ok, conn}, fn payload, {:ok, conn} ->
      case chunk(conn, sse_data(payload)) do
        {:ok, conn} -> {:cont, {:ok, conn}}
        {:error, reason} -> {:halt, {:error, reason, conn}}
      end
    end)
  end

  defp write_sse_done(conn) do
    case chunk(conn, "data: [DONE]\n\n") do
      {:ok, conn} ->
        conn

      {:error, reason} ->
        tap(conn, fn _conn -> Logger.warning("Could not write SSE done: #{inspect(reason)}") end)
    end
  end

  defp write_sse_error(conn, reason) do
    payload = %{error: %{code: error_code(reason), message: elem(error_details(reason), 2)}}

    case chunk(conn, "event: error\n" <> sse_data(payload) <> "data: [DONE]\n\n") do
      {:ok, conn} ->
        conn

      {:error, reason} ->
        tap(conn, fn _conn -> Logger.warning("Could not write SSE error: #{inspect(reason)}") end)
    end
  end

  defp sse_data(payload), do: "data: #{Jason.encode!(payload)}\n\n"

  defp error_code(reason) do
    {_status, code, _message} = error_details(reason)
    code
  end

  defp error_details(:missing_file),
    do: {:bad_request, "missing_file", "Upload a file in the image or file field."}

  defp error_details(:empty_file),
    do: {:bad_request, "empty_file", "Uploaded file is empty."}

  defp error_details(:file_too_large),
    do: {:payload_too_large, "file_too_large", "Uploaded file exceeds 16 MB."}

  defp error_details(:unsupported_media_type),
    do:
      {:unsupported_media_type, "unsupported_media_type",
       "Only png, jpg, jpeg, and gif images are supported."}

  defp error_details(:empty_prompt),
    do: {:bad_request, "empty_prompt", "Question must not be empty."}

  defp error_details(:not_found),
    do: {:not_found, "not_found", "Image was not found."}

  defp error_details(:storage_missing),
    do: {:not_found, "storage_missing", "Image file was missing and stale data was removed."}

  defp error_details(%Ash.Error.Invalid{}),
    do: {:unprocessable_entity, "validation_failed", "Request could not be saved."}

  defp error_details(_reason),
    do: {:internal_server_error, "internal_error", "Request could not be completed."}
end
