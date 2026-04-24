defmodule Inkit.RateLimiter do
  @moduledoc false

  use GenServer

  @table __MODULE__
  @default_window_ms 60_000
  @default_max_requests 60

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def check(key, opts \\ []) do
    if enabled?() do
      window_ms = Keyword.get(opts, :window_ms, config(:window_ms, @default_window_ms))

      max_requests =
        Keyword.get(opts, :max_requests, config(:max_requests, @default_max_requests))

      now = System.monotonic_time(:millisecond)
      bucket = div(now, window_ms)
      expires_at = (bucket + 1) * window_ms

      count = :ets.update_counter(@table, {key, bucket}, {2, 1}, {{key, bucket}, 0, expires_at})

      if count > max_requests do
        reset_ms = max(expires_at - now, 0)
        {:error, :rate_limited, %{retry_after_ms: reset_ms, limit: max_requests}}
      else
        {:ok, %{remaining: max_requests - count, reset_ms: expires_at - now}}
      end
    else
      {:ok, %{remaining: :infinity, reset_ms: 0}}
    end
  end

  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    # match spec: rows whose expires_at (3rd element) is <= now
    match = [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}]
    :ets.select_delete(@table, match)
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, :timer.minutes(5))
  end

  defp enabled? do
    config(:enabled, true)
  end

  defp config(key, default) do
    :inkit
    |> Application.get_env(:rate_limit, [])
    |> Keyword.get(key, default)
  end
end
