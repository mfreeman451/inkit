defmodule InkitWeb.VisualAssistantController do
  use InkitWeb, :controller

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

  defp fetch_upload(%{"image" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp fetch_upload(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp fetch_upload(_params), do: {:error, :missing_file}

  defp prompt_param(params) do
    params["prompt"] || params["question"] || params["message"] || ""
  end

  defp error(conn, reason) do
    {status, code, message} =
      case reason do
        :missing_file ->
          {:bad_request, "missing_file", "Upload a file in the image or file field."}

        :empty_file ->
          {:bad_request, "empty_file", "Uploaded file is empty."}

        :file_too_large ->
          {:payload_too_large, "file_too_large", "Uploaded file exceeds 16 MB."}

        :unsupported_media_type ->
          {:unsupported_media_type, "unsupported_media_type",
           "Only png, jpg, jpeg, and gif images are supported."}

        :empty_prompt ->
          {:bad_request, "empty_prompt", "Question must not be empty."}

        :not_found ->
          {:not_found, "not_found", "Image was not found."}

        %Ash.Error.Invalid{} ->
          {:unprocessable_entity, "validation_failed", "Request could not be saved."}

        _ ->
          {:internal_server_error, "internal_error", "Request could not be completed."}
      end

    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end
