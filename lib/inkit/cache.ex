defmodule Inkit.Cache do
  @moduledoc false

  use GenServer

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if expires_at == :infinity or System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          delete(key)
          :miss
        end

      [] ->
        :miss
    end
  end

  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, :timer.minutes(5))

    expires_at =
      case ttl do
        :infinity -> :infinity
        ttl when is_integer(ttl) -> System.monotonic_time(:millisecond) + ttl
      end

    true = :ets.insert(@table, {key, value, expires_at})
    :ok
  end

  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end
end
