defmodule Inkit.Release.SqliteCompatibility do
  @moduledoc false

  require Logger

  @schema_migrations_table "schema_migrations"
  @inserted_at_column "inserted_at"
  @uploaded_images_table "uploaded_images"
  @demo_upload_prefix "/app/demo/uploads/"

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      restart: :temporary,
      type: :worker
    }
  end

  def start_link(_opts) do
    ensure_schema_migrations_timestamp()
    normalize_demo_upload_paths()
    :ignore
  end

  defp ensure_schema_migrations_timestamp do
    case Inkit.Repo.query("PRAGMA table_info(#{@schema_migrations_table})", []) do
      {:ok, %{rows: []}} ->
        :ok

      {:ok, %{rows: rows}} ->
        unless Enum.any?(rows, &column_named?(&1, @inserted_at_column)) do
          Inkit.Repo.query!(
            "ALTER TABLE #{@schema_migrations_table} ADD COLUMN #{@inserted_at_column} TEXT",
            []
          )
        end

        Inkit.Repo.query!(
          "UPDATE #{@schema_migrations_table} SET #{@inserted_at_column} = COALESCE(#{@inserted_at_column}, datetime('now'))",
          []
        )

        :ok

      {:error, error} ->
        raise error
    end
  end

  defp column_named?(row, name) do
    Enum.at(row, 1) == name
  end

  defp normalize_demo_upload_paths do
    upload_dir = Application.get_env(:inkit, :upload_dir)

    with true <- is_binary(upload_dir),
         :ok <- table_exists?(@uploaded_images_table),
         {:ok, %{rows: rows}} <-
           Inkit.Repo.query(
             "SELECT id, storage_path FROM #{@uploaded_images_table} WHERE storage_path LIKE ?",
             [@demo_upload_prefix <> "%"]
           ) do
      File.mkdir_p!(upload_dir)

      Enum.each(rows, fn [id, source_path] ->
        normalize_demo_upload_path(id, source_path, upload_dir)
      end)
    else
      false -> :ok
      :skip -> :ok
      {:error, error} -> raise error
    end
  end

  defp table_exists?(table_name) do
    case Inkit.Repo.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", [
           table_name
         ]) do
      {:ok, %{rows: []}} -> :skip
      {:ok, %{rows: [_ | _]}} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp normalize_demo_upload_path(id, source_path, upload_dir) do
    target_path = Path.join(upload_dir, Path.basename(source_path))

    cond do
      File.exists?(target_path) ->
        update_storage_path(id, target_path)

      File.exists?(source_path) ->
        case File.cp(source_path, target_path) do
          :ok ->
            update_storage_path(id, target_path)

          {:error, reason} ->
            Logger.warning(
              "Could not copy demo upload #{source_path} to #{target_path}: #{inspect(reason)}"
            )
        end

      true ->
        :ok
    end
  end

  defp update_storage_path(id, target_path) do
    Inkit.Repo.query!(
      "UPDATE #{@uploaded_images_table} SET storage_path = ? WHERE id = ?",
      [target_path, id]
    )
  end
end
