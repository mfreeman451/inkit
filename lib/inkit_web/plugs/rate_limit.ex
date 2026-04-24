defmodule InkitWeb.Plugs.RateLimit do
  @moduledoc false

  import Plug.Conn

  alias Inkit.RateLimiter

  def init(opts) do
    bucket = Keyword.fetch!(opts, :bucket)

    %{
      bucket: bucket,
      max_requests: Keyword.get(opts, :max_requests),
      window_ms: Keyword.get(opts, :window_ms)
    }
  end

  def call(conn, %{bucket: bucket} = opts) do
    key = {bucket, client_ip(conn)}

    case RateLimiter.check(key, limiter_opts(opts)) do
      {:ok, info} ->
        put_rate_limit_headers(conn, info)

      {:error, :rate_limited, info} ->
        retry_after_s = max(ceil(info.retry_after_ms / 1000), 1)

        conn
        |> put_rate_limit_headers(Map.put(info, :remaining, 0))
        |> put_resp_header("retry-after", Integer.to_string(retry_after_s))
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          Jason.encode!(%{
            error: %{
              code: "rate_limited",
              message: "Too many requests. Try again in #{retry_after_s}s."
            }
          })
        )
        |> halt()
    end
  end

  defp limiter_opts(%{max_requests: nil, window_ms: nil}), do: []

  defp limiter_opts(%{max_requests: max_requests, window_ms: window_ms}) do
    []
    |> put_unless_nil(:max_requests, max_requests)
    |> put_unless_nil(:window_ms, window_ms)
  end

  defp put_unless_nil(kw, _key, nil), do: kw
  defp put_unless_nil(kw, key, value), do: Keyword.put(kw, key, value)

  defp put_rate_limit_headers(conn, info) do
    conn
    |> maybe_put_header("x-ratelimit-remaining", info[:remaining] || info.remaining)
    |> maybe_put_header("x-ratelimit-reset-ms", info[:reset_ms] || Map.get(info, :reset_ms, 0))
  end

  defp maybe_put_header(conn, _name, :infinity), do: conn

  defp maybe_put_header(conn, name, value) when is_integer(value) do
    put_resp_header(conn, name, Integer.to_string(value))
  end

  defp maybe_put_header(conn, _name, _value), do: conn

  defp client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [value | _] ->
        value
        |> String.split(",")
        |> List.first()
        |> to_string()
        |> String.trim()

      [] ->
        case conn.remote_ip do
          nil -> "unknown"
          tuple -> tuple |> :inet.ntoa() |> to_string()
        end
    end
  end
end
