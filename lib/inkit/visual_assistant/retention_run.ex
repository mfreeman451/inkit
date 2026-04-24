defmodule Inkit.VisualAssistant.RetentionRun do
  @moduledoc """
  Record of a single retention sweep. Written by the scheduler on every tick
  (and by manual runs from the UI) so reviewers can see the job is live.
  """

  use Ash.Resource,
    domain: Inkit.VisualAssistant,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "retention_runs"
    repo Inkit.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :started_at,
        :finished_at,
        :duration_ms,
        :status,
        :triggered_by,
        :messages_deleted,
        :api_logs_deleted,
        :images_deleted,
        :error_message
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :finished_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :duration_ms, :integer do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:ok, :error]
    end

    attribute :triggered_by, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:scheduled, :manual, :startup]
    end

    attribute :messages_deleted, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :api_logs_deleted, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :images_deleted, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :error_message, :string do
      public? true
    end

    create_timestamp :inserted_at
  end
end
