defmodule Inkit.VisualAssistant.RetentionSetting do
  @moduledoc """
  Singleton resource holding the retention windows the scheduler reads on each
  tick. One row is maintained at `@singleton_id`; the helper functions in this
  module ensure the row exists and expose read/update paths used by the UI.
  """

  use Ash.Resource,
    domain: Inkit.VisualAssistant,
    data_layer: AshSqlite.DataLayer

  @singleton_id "00000000-0000-0000-0000-000000000001"

  @default_messages_days 30
  @default_api_logs_days 7
  @default_images_days 30
  @default_interval_minutes 60

  sqlite do
    table "retention_settings"
    repo Inkit.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :enabled,
        :messages_days,
        :api_logs_days,
        :images_days,
        :interval_minutes
      ]
    end

    update :update_windows do
      accept [:enabled, :messages_days, :api_logs_days, :images_days, :interval_minutes]
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :messages_days, :integer do
      allow_nil? false
      default @default_messages_days
      public? true
      constraints min: 1, max: 3650
    end

    attribute :api_logs_days, :integer do
      allow_nil? false
      default @default_api_logs_days
      public? true
      constraints min: 1, max: 3650
    end

    attribute :images_days, :integer do
      allow_nil? false
      default @default_images_days
      public? true
      constraints min: 1, max: 3650
    end

    attribute :interval_minutes, :integer do
      allow_nil? false
      default @default_interval_minutes
      public? true
      constraints min: 1, max: 1440
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  def singleton_id, do: @singleton_id

  def defaults do
    %{
      enabled: @default_messages_days && true,
      messages_days: @default_messages_days,
      api_logs_days: @default_api_logs_days,
      images_days: @default_images_days,
      interval_minutes: @default_interval_minutes
    }
  end

  def fetch do
    case Ash.get(__MODULE__, @singleton_id) do
      {:ok, setting} ->
        {:ok, setting}

      {:error, %Ash.Error.Invalid{}} ->
        ensure_exists()

      {:error, %Ash.Error.Query.NotFound{}} ->
        ensure_exists()

      {:error, _} = err ->
        err
    end
  end

  def ensure_exists do
    attrs = Map.put(defaults(), :id, @singleton_id)

    __MODULE__
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
    |> case do
      {:ok, setting} -> {:ok, setting}
      {:error, %Ash.Error.Invalid{}} -> Ash.get(__MODULE__, @singleton_id)
      other -> other
    end
  end

  def update(attrs) do
    with {:ok, setting} <- fetch() do
      setting
      |> Ash.Changeset.for_update(:update_windows, attrs)
      |> Ash.update()
    end
  end
end
