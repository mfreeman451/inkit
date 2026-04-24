defmodule Inkit.VisualAssistant.UploadedImage do
  @moduledoc false

  use Ash.Resource,
    domain: Inkit.VisualAssistant,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "uploaded_images"
    repo Inkit.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:public_id, :original_filename, :content_type, :size, :storage_path, :sha256]
    end

    update :update_label do
      accept [:label]
    end

    read :by_public_id do
      get? true

      argument :public_id, :string do
        allow_nil? false
      end

      filter expr(public_id == ^arg(:public_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :public_id, :string do
      allow_nil? false
      public? true
    end

    attribute :original_filename, :string do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      public? true
    end

    attribute :content_type, :string do
      allow_nil? false
      public? true
    end

    attribute :size, :integer do
      allow_nil? false
      public? true
    end

    attribute :storage_path, :string do
      allow_nil? false
      public? true
    end

    attribute :sha256, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :messages, Inkit.VisualAssistant.Message do
      destination_attribute :uploaded_image_id
    end
  end

  identities do
    identity :unique_public_id, [:public_id]
  end
end
