defmodule Inkit.VisualAssistant.Retention do
  @moduledoc """
  Periodically purges old conversation history, API logs, and orphaned images.

  Windows are persisted in `Inkit.VisualAssistant.RetentionSetting` (singleton
  row, editable via the Settings UI). Every sweep — scheduled, startup, or
  manual — writes an `Inkit.VisualAssistant.RetentionRun` record so the UI can
  show the evaluator that the job actually fires.
  """

  use GenServer

  require Ash.Query
  require Logger

  alias Inkit.VisualAssistant.{
    ApiLog,
    Message,
    RetentionRun,
    RetentionSetting,
    UploadedImage,
    Workflows
  }

  @default_interval_minutes 60

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Run a sweep synchronously. Returns `{:ok, run_record}`."
  def run_now(opts \\ []) do
    GenServer.call(__MODULE__, {:run_now, opts}, :timer.seconds(30))
  end

  @impl true
  def init(_opts) do
    if scheduler_enabled?() do
      schedule_tick(0)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    sweep(triggered_by: :scheduled)
    schedule_tick(interval_ms())
    {:noreply, state}
  end

  @impl true
  def handle_call({:run_now, opts}, _from, state) do
    opts = Keyword.put_new(opts, :triggered_by, :manual)
    {:reply, sweep(opts), state}
  end

  defp sweep(opts) do
    triggered_by = Keyword.get(opts, :triggered_by, :manual)
    started_at = DateTime.utc_now()
    start_monotonic = System.monotonic_time(:millisecond)

    windows = resolve_windows(opts)

    {counts, status, error_message} =
      try do
        {perform_sweep(started_at, windows), :ok, nil}
      rescue
        error ->
          Logger.warning("retention: sweep failed: #{Exception.message(error)}")
          {%{messages: 0, api_logs: 0, images: 0}, :error, Exception.message(error)}
      end

    finished_at = DateTime.utc_now()
    duration_ms = System.monotonic_time(:millisecond) - start_monotonic

    record =
      record_run!(%{
        started_at: started_at,
        finished_at: finished_at,
        duration_ms: duration_ms,
        status: status,
        triggered_by: triggered_by,
        messages_deleted: counts.messages,
        api_logs_deleted: counts.api_logs,
        images_deleted: counts.images,
        error_message: error_message
      })

    Logger.info(
      "retention sweep (#{triggered_by}): messages=#{counts.messages} api_logs=#{counts.api_logs} images=#{counts.images}"
    )

    {:ok, record}
  end

  defp resolve_windows(opts) do
    case RetentionSetting.fetch() do
      {:ok, setting} ->
        %{
          messages_days: Keyword.get(opts, :messages_days, setting.messages_days),
          api_logs_days: Keyword.get(opts, :api_logs_days, setting.api_logs_days),
          images_days: Keyword.get(opts, :images_days, setting.images_days),
          interval_minutes: setting.interval_minutes,
          enabled: setting.enabled
        }

      {:error, _} ->
        defaults = RetentionSetting.defaults()

        %{
          messages_days: Keyword.get(opts, :messages_days, defaults.messages_days),
          api_logs_days: Keyword.get(opts, :api_logs_days, defaults.api_logs_days),
          images_days: Keyword.get(opts, :images_days, defaults.images_days),
          interval_minutes: defaults.interval_minutes,
          enabled: defaults.enabled
        }
    end
  end

  defp perform_sweep(now, windows) do
    %{
      messages: purge_messages(cutoff(now, windows.messages_days)),
      api_logs: purge_api_logs(cutoff(now, windows.api_logs_days)),
      images: purge_images(cutoff(now, windows.images_days))
    }
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

  defp cutoff(now, days) do
    DateTime.add(now, -days * 86_400, :second)
  end

  defp record_run!(attrs) do
    RetentionRun
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  defp schedule_tick(delay_ms) do
    Process.send_after(self(), :tick, delay_ms)
  end

  defp scheduler_enabled? do
    :inkit
    |> Application.get_env(:retention, [])
    |> Keyword.get(:enabled, true)
  end

  defp interval_ms do
    case RetentionSetting.fetch() do
      {:ok, setting} -> setting.interval_minutes * 60_000
      _ -> @default_interval_minutes * 60_000
    end
  end
end
