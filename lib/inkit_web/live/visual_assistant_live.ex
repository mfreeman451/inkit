defmodule InkitWeb.VisualAssistantLive do
  use InkitWeb, :live_view

  alias Inkit.VisualAssistant.Workflows, as: VisualAssistant

  @impl true
  def mount(_params, _session, socket) do
    recent_images = recent_images()
    api_log_page = api_logs_page(1)

    socket =
      socket
      |> assign(:image, nil)
      |> assign(:analysis, nil)
      |> assign(:messages, [])
      |> assign(:question, "")
      |> assign(:streaming, false)
      |> assign(:streamed_response, "")
      |> assign(:error, nil)
      |> assign(:recent_images, recent_images)
      |> assign(:conversation_summaries, conversation_summaries(recent_images))
      |> assign(:api_logs, api_log_page.logs)
      |> assign(:api_log_page, api_log_page.page)
      |> assign(:api_log_page_size, api_log_page.page_size)
      |> assign(:api_log_total, api_log_page.total)
      |> assign(:image_activity_logs, [])
      |> assign(:usage_summary, VisualAssistant.usage_summary())
      |> assign(:conversation_view, :index)
      |> assign(:active_tab, :details)
      |> assign(:active_section, :conversations)
      |> allow_upload(:image,
        accept: ~w(.png .jpg .jpeg .gif),
        max_entries: 1,
        max_file_size: 16 * 1024 * 1024
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, assign(socket, :error, nil)}
  end

  def handle_event("upload", _params, socket) do
    results =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        case VisualAssistant.create_image_from_upload(path, entry.client_name, entry.client_type) do
          {:ok, image, analysis} -> {:ok, {image, analysis}}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case results do
      [{image, analysis}] ->
        VisualAssistant.record_api_log(%{
          method: "LIVE",
          path: "/live/upload",
          status: 201,
          duration_ms: 0,
          image_public_id: image.public_id
        })

        {:noreply,
         socket
         |> assign(:image, image)
         |> assign(:analysis, analysis)
         |> assign(:messages, [])
         |> assign(:image_activity_logs, image_activity_logs(image))
         |> assign(:streamed_response, "")
         |> assign(:error, nil)
         |> assign(:active_section, :conversations)
         |> assign(:conversation_view, :show)
         |> refresh_dashboard_data()}

      [{:error, reason}] ->
        {:noreply, assign(socket, :error, human_error(reason))}

      [] ->
        {:noreply, assign(socket, :error, "Choose an image before uploading.")}
    end
  end

  def handle_event("ask", %{"question" => question}, %{assigns: %{image: nil}} = socket) do
    {:noreply, socket |> assign(:question, question) |> assign(:error, "Upload an image first.")}
  end

  def handle_event("ask", %{"question" => question}, socket) do
    case VisualAssistant.prepare_stream(socket.assigns.image.public_id, question) do
      {:ok, stream} ->
        send(self(), {:stream_chat, stream, stream.chunks})

        {:noreply,
         socket
         |> assign(:question, "")
         |> assign(:streaming, true)
         |> assign(:streamed_response, "")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("set_tab", %{"tab" => tab}, socket)
      when tab in ["details", "memory", "activity"] do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("set_section", %{"section" => section}, socket)
      when section in ["conversations", "uploads", "api_logs", "settings", "docs"] do
    socket =
      socket
      |> assign(:active_section, section_atom(section))
      |> assign(:error, nil)

    socket =
      if section == "conversations" do
        assign(socket, :conversation_view, :index)
      else
        socket
      end

    {:noreply, refresh_dashboard_data(socket)}
  end

  def handle_event("set_section", _params, socket), do: {:noreply, socket}

  def handle_event("show_conversation_index", _params, socket) do
    {:noreply,
     socket
     |> assign(:active_section, :conversations)
     |> assign(:conversation_view, :index)
     |> assign(:error, nil)
     |> refresh_dashboard_data()}
  end

  def handle_event("api_logs_page", %{"direction" => direction}, socket)
      when direction in ["previous", "next"] do
    page =
      case direction do
        "previous" -> max(socket.assigns.api_log_page - 1, 1)
        "next" -> socket.assigns.api_log_page + 1
      end

    {:noreply, assign_api_logs_page(socket, page)}
  end

  def handle_event("new_conversation", _params, socket) do
    {:noreply,
     socket
     |> assign(:image, nil)
     |> assign(:analysis, nil)
     |> assign(:messages, [])
     |> assign(:image_activity_logs, [])
     |> assign(:question, "")
     |> assign(:streaming, false)
     |> assign(:streamed_response, "")
     |> assign(:error, nil)
     |> assign(:conversation_view, :new)
     |> assign(:active_section, :conversations)}
  end

  def handle_event("load_image", %{"image-id" => public_id}, socket) do
    case VisualAssistant.load_conversation(public_id) do
      {:ok, image, analysis, messages} ->
        {:noreply,
         socket
         |> assign(:image, image)
         |> assign(:analysis, analysis)
         |> assign(:messages, messages)
         |> assign(:image_activity_logs, image_activity_logs(image))
         |> assign(:question, "")
         |> assign(:streaming, false)
         |> assign(:streamed_response, "")
         |> assign(:error, nil)
         |> assign(:active_section, :conversations)
         |> assign(:conversation_view, :show)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:conversation_view, :index)
         |> assign(:error, human_error(reason))
         |> refresh_dashboard_data()}
    end
  end

  def handle_event("update_label", %{"image-id" => public_id, "label" => label}, socket) do
    case VisualAssistant.update_image_label(public_id, label) do
      {:ok, image} ->
        {:noreply,
         socket
         |> maybe_replace_active_image(image)
         |> assign(:error, nil)
         |> assign(:active_section, :uploads)
         |> refresh_dashboard_data()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("delete_image", %{"image-id" => public_id}, socket) do
    case VisualAssistant.delete_image(public_id) do
      :ok ->
        {:noreply,
         socket
         |> maybe_clear_active_image(public_id)
         |> assign(:error, nil)
         |> assign(:active_section, :uploads)
         |> refresh_dashboard_data()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("clear_all", _params, socket) do
    case VisualAssistant.clear_all() do
      :ok ->
        {:noreply,
         socket
         |> assign(:image, nil)
         |> assign(:analysis, nil)
         |> assign(:messages, [])
         |> assign(:image_activity_logs, [])
         |> assign(:question, "")
         |> assign(:streaming, false)
         |> assign(:streamed_response, "")
         |> assign(:recent_images, [])
         |> assign(:conversation_summaries, [])
         |> assign_api_logs_page(1)
         |> assign(:usage_summary, VisualAssistant.usage_summary())
         |> assign(:conversation_view, :index)
         |> assign(:error, nil)
         |> assign(:active_section, :settings)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  @impl true
  def handle_info({:stream_chat, stream, chunks}, socket) do
    if active_stream?(socket, stream) do
      handle_active_stream(stream, chunks, socket)
    else
      {:noreply, socket}
    end
  end

  defp handle_active_stream(stream, [chunk | rest], socket) do
    content =
      chunk
      |> get_in(["choices", Access.at(0), "delta", "content"])
      |> case do
        nil -> ""
        value -> value
      end

    Process.send_after(self(), {:stream_chat, stream, rest}, 25)
    {:noreply, update(socket, :streamed_response, &(&1 <> content))}
  end

  defp handle_active_stream(stream, [], socket) do
    case VisualAssistant.persist_stream(stream) do
      :ok ->
        VisualAssistant.record_api_log(%{
          method: "LIVE",
          path: "/live/chat",
          status: 200,
          duration_ms: 0,
          image_public_id: stream.image.public_id
        })

        {:ok, messages} = VisualAssistant.list_messages(stream.image.public_id)

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:image_activity_logs, image_activity_logs(stream.image))
         |> assign(:streaming, false)
         |> assign(:streamed_response, "")
         |> assign(:conversation_view, :show)
         |> refresh_dashboard_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:streaming, false)
         |> assign(:streamed_response, "")
         |> assign(:error, human_error(reason))}
    end
  end

  defp active_stream?(
         %{assigns: %{streaming: true, image: %{public_id: public_id}}},
         %{image: %{public_id: public_id}}
       ),
       do: true

  defp active_stream?(_socket, _stream), do: false

  defp human_error(:empty_prompt), do: "Ask a question before sending."

  defp human_error(:unsupported_media_type),
    do: "Only png, jpg, jpeg, and gif images are supported."

  defp human_error(:file_too_large), do: "Uploaded file exceeds 16 MB."
  defp human_error(:missing_file), do: "Choose an image before uploading."
  defp human_error(:not_found), do: "Conversation was not found. Refreshing the list."
  defp human_error(:storage_missing), do: "Image file was missing. Removed stale conversation."
  defp human_error(_reason), do: "Request could not be completed."

  defp recent_images do
    case VisualAssistant.list_recent_images() do
      {:ok, images} -> images
      {:error, _reason} -> []
    end
  end

  defp refresh_dashboard_data(socket) do
    recent_images = recent_images()

    socket
    |> assign(:recent_images, recent_images)
    |> assign(:conversation_summaries, conversation_summaries(recent_images))
    |> assign_api_logs_page(socket.assigns[:api_log_page] || 1)
    |> assign(:usage_summary, VisualAssistant.usage_summary())
  end

  defp assign_api_logs_page(socket, page) do
    page_data = api_logs_page(page, socket.assigns[:api_log_page_size] || 25)

    socket
    |> assign(:api_logs, page_data.logs)
    |> assign(:api_log_page, page_data.page)
    |> assign(:api_log_page_size, page_data.page_size)
    |> assign(:api_log_total, page_data.total)
  end

  defp api_logs_page(page, page_size \\ 25) do
    case VisualAssistant.list_api_logs_page(page, page_size) do
      {:ok, [], total} when page > 1 and total > 0 ->
        page_count = ceil(total / page_size)
        api_logs_page(page_count, page_size)

      {:ok, logs, total} ->
        %{logs: logs, page: page, page_size: page_size, total: total}

      {:error, _reason} ->
        %{logs: [], page: 1, page_size: page_size, total: 0}
    end
  end

  defp image_activity_logs(nil), do: []

  defp image_activity_logs(image) do
    case VisualAssistant.list_api_logs_for_image(image.public_id, 10) do
      {:ok, logs} -> logs
      {:error, _reason} -> []
    end
  end

  defp conversation_summaries(images) do
    messages_by_image_id =
      case VisualAssistant.list_messages_for_images(images) do
        {:ok, messages_by_image_id} -> messages_by_image_id
        {:error, _reason} -> %{}
      end

    Enum.map(images, fn image ->
      messages = Map.get(messages_by_image_id, image.id, [])

      %{
        image: image,
        message_count: length(messages),
        last_user_message: last_user_message(messages)
      }
    end)
  end

  defp last_user_message(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(&(&1.role == "user"))
    |> case do
      nil -> nil
      message -> message.content
    end
  end

  defp maybe_replace_active_image(
         %{assigns: %{image: %{public_id: public_id}}} = socket,
         %{
           public_id: public_id
         } = image
       ) do
    assign(socket, :image, image)
  end

  defp maybe_replace_active_image(socket, _image), do: socket

  defp maybe_clear_active_image(%{assigns: %{image: %{public_id: public_id}}} = socket, public_id) do
    socket
    |> assign(:image, nil)
    |> assign(:analysis, nil)
    |> assign(:messages, [])
    |> assign(:image_activity_logs, [])
    |> assign(:question, "")
    |> assign(:streaming, false)
    |> assign(:streamed_response, "")
  end

  defp maybe_clear_active_image(socket, _public_id), do: socket

  defp image_tags(nil), do: []

  defp image_tags(%{original_filename: filename}) do
    filename = String.downcase(filename)

    cond do
      String.contains?(filename, ["kitchen", "renovation"]) ->
        ["kitchen", "modern farmhouse", "white cabinetry", "quartz counters", "pendant lighting"]

      String.contains?(filename, ["bathroom", "bath", "shower", "tub", "vanity"]) ->
        ["bathroom", "spa bath", "marble-look tile", "matte black fixtures", "freestanding tub"]

      true ->
        ["uploaded image", "mock analysis", "ready for questions"]
    end
  end

  defp page_title(:conversations, :index, _image), do: "Conversations"
  defp page_title(:conversations, :new, _image), do: "New visual analysis"

  defp page_title(:conversations, :show, image),
    do: image.label || Path.rootname(image.original_filename)

  defp page_title(:uploads, _view, _image), do: "Uploads"
  defp page_title(:api_logs, _view, _image), do: "API Logs"
  defp page_title(:settings, _view, _image), do: "Settings"
  defp page_title(:docs, _view, _image), do: "Docs"

  defp page_count(total, page_size) when total > 0, do: ceil(total / page_size)
  defp page_count(_total, _page_size), do: 1

  defp file_size(size) when is_integer(size) and size >= 1_048_576 do
    "#{Float.round(size / 1_048_576, 1)} MB"
  end

  defp file_size(size) when is_integer(size) and size >= 1024 do
    "#{Float.round(size / 1024, 1)} KB"
  end

  defp file_size(size) when is_integer(size), do: "#{size} bytes"
  defp file_size(_size), do: "unknown size"

  defp section_atom("conversations"), do: :conversations
  defp section_atom("uploads"), do: :uploads
  defp section_atom("api_logs"), do: :api_logs
  defp section_atom("settings"), do: :settings
  defp section_atom("docs"), do: :docs
end
