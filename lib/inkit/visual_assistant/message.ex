defmodule Inkit.VisualAssistant.Message do
  @moduledoc false

  use Ash.Resource,
    domain: Inkit.VisualAssistant,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "conversation_messages"
    repo Inkit.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:uploaded_image_id, :role, :content, :response_id]
    end

    read :for_image do
      argument :uploaded_image_id, :uuid do
        allow_nil? false
      end

      filter expr(uploaded_image_id == ^arg(:uploaded_image_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :string do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :response_id, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :uploaded_image, Inkit.VisualAssistant.UploadedImage do
      allow_nil? false
      public? true
    end
  end
end
