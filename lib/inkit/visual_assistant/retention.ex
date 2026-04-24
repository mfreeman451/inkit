defmodule Inkit.VisualAssistant.Retention do
  @moduledoc """
  Periodically purges old conversation history, API logs, and orphaned images.

  Windows are configured under `config :inkit, :retention, ...`. The GenServer
  ticks at `:interval_ms`. Call `run_now/0` to purge on demand (used by tests
  and an ops-level trigger).
  """

  use GenServer

  require Ash.Query
  require Logger

  alias Inkit.VisualAssistant.{ApiLog, Message, UploadedImage, Workflows}

  @default_interval_ms :timer.hours(1)
  @default_messages_days 30
  @default_api_logs_days 7
  @default_images_days 30

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Run a retention sweep synchronously. Returns a map of counts."
  def run_now(opts \\ []) do
    GenServer.call(__MODULE__, {:run_now, opts}, :timer.seconds(30))
  end

  @impl true
  def init(_opts) do
    if enabled?() do
      schedule_tick(0)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    sweep([])
    schedule_tick(interval_ms())
    {:noreply, state}
  end

  @impl true
  def handle_call({:run_now, opts}, _from, state) do
    {:reply, sweep(opts), state}
  end

  defp sweep(opts) do
    now = DateTime.utc_now()

    messages_cutoff = cutoff(now, :messages_days, opts, @default_messages_days)
    api_logs_cutoff = cutoff(now, :api_logs_days, opts, @default_api_logs_days)
    images_cutoff = cutoff(now, :images_days, opts, @default_images_days)

    counts = %{
      messages: purge_messages(messages_cutoff),
      api_logs: purge_api_logs(api_logs_cutoff),
      images: purge_images(images_cutoff)
    }

    Logger.info("retention sweep: #{inspect(counts)}")
    counts
  end

  defp purge_messages(cutoff) do
    Message
    |> Ash.Query.for_read(:read)
    |> Ash.Query.filter(inserted_at < ^cutoff)
    |> Ash.read()
    |> case do
      {:ok, records} ->
        Enum.each(records, &Ash.destroy!/1)
        length(records)

      {:error, reason} ->
        Logger.warning("retention: could not read messages: #{inspect(reason)}")
        0
    end
  end

  defp purge_api_logs(cutoff) do
    ApiLog
    |> Ash.Query.for_read(:read)
    |> Ash.Query.filter(inserted_at < ^cutoff)
    |> Ash.read()
    |> case do
      {:ok, records} ->
        Enum.each(records, &Ash.destroy!/1)
        length(records)

      {:error, reason} ->
        Logger.warning("retention: could not read api_logs: #{inspect(reason)}")
        0
    end
  end

  defp purge_images(cutoff) do
    UploadedImage
    |> Ash.Query.for_read(:read)
    |> Ash.Query.filter(inserted_at < ^cutoff)
    |> Ash.read()
    |> case do
      {:ok, records} ->
        records |> Enum.map(&delete_image/1) |> Enum.sum()

      {:error, reason} ->
        Logger.warning("retention: could not read images: #{inspect(reason)}")
        0
    end
  end

  defp delete_image(image) do
    case Workflows.delete_image(image.public_id) do
      :ok ->
        1

      {:error, reason} ->
        Logger.warning("retention: could not delete image #{image.public_id}: #{inspect(reason)}")

        0
    end
  end

  defp cutoff(now, key, opts, default_days) do
    days = Keyword.get(opts, key) || config(key, default_days)
    DateTime.add(now, -days * 86_400, :second)
  end

  defp schedule_tick(delay_ms) do
    Process.send_after(self(), :tick, delay_ms)
  end

  defp enabled? do
    config(:enabled, true)
  end

  defp interval_ms do
    config(:interval_ms, @default_interval_ms)
  end

  defp config(key, default) do
    :inkit
    |> Application.get_env(:retention, [])
    |> Keyword.get(key, default)
  end
end
