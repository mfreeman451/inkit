defmodule Inkit.VisualAssistant.ApiLog do
  @moduledoc false

  use Ash.Resource,
    domain: Inkit.VisualAssistant,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "api_logs"
    repo Inkit.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:method, :path, :status, :duration_ms, :image_public_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :method, :string do
      allow_nil? false
      public? true
    end

    attribute :path, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :integer do
      allow_nil? false
      public? true
    end

    attribute :duration_ms, :integer do
      allow_nil? false
      public? true
    end

    attribute :image_public_id, :string do
      public? true
    end

    create_timestamp :inserted_at
  end
end
