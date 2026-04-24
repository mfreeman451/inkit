defmodule InkitWeb.Plugs.ApiLogPlug do
  @moduledoc false

  import Plug.Conn

  alias Inkit.VisualAssistant.Workflows

  def init(opts), do: opts

  def call(conn, _opts) do
    start_time = System.monotonic_time(:microsecond)

    register_before_send(conn, fn conn ->
      duration_ms =
        System.monotonic_time(:microsecond)
        |> Kernel.-(start_time)
        |> div(1000)

      Workflows.record_api_log_async(%{
        method: conn.method,
        path: conn.request_path,
        status: conn.status || 0,
        duration_ms: duration_ms,
        image_public_id: conn.path_params["image_id"]
      })

      conn
    end)
  end
end
