defmodule Inkit.Repo.Migrations.AddUploadedImageLabels do
  use Ecto.Migration

  def change do
    alter table(:uploaded_images) do
      add :label, :text
    end
  end
end
