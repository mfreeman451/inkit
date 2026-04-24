defmodule Inkit.Release.SqliteCompatibility do
  @moduledoc false

  @schema_migrations_table "schema_migrations"
  @inserted_at_column "inserted_at"

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
end
