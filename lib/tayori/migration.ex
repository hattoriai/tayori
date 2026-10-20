defmodule Tayori.Migration do
  @moduledoc """
  The tables of Tayori, in a migration of the app.

      $ mix tayori.gen.migration

  writes a migration that calls this module:

      defmodule MyApp.Repo.Migrations.AddTayori do
        use Ecto.Migration

        def up, do: Tayori.Migration.up(version: 1)
        def down, do: Tayori.Migration.down(version: 1)
      end

  The tables:

    * `tayori_entries` - an entry of the news: its slug, categories, the
      segments of readers it is for, and when it is published (nil while it
      is a draft);
    * `tayori_translations` - the title, summary and body of an entry, one
      row for each language;
    * `tayori_reads` - for each reader, when they last saw the news;
    * `tayori_settings` - the settings of the admin, such as the AI model
      and its key, encrypted.

  The migration runs on PostgreSQL and on SQLite. A later version of
  Tayori that changes the tables will have a version 2, and a migration of
  the app that calls `up(version: 2)`.

  Options: `:version` (1, the only one), `:prefix` (the schema of the
  tables, in PostgreSQL).
  """

  use Ecto.Migration

  @current 1

  @doc "Creates the tables and their indexes."
  @spec up(keyword()) :: :ok
  def up(opts \\ []) do
    version = Keyword.get(opts, :version, @current)
    prefix = opts[:prefix]

    if version >= 1 do
      create_if_not_exists table(:tayori_entries, primary_key: false, prefix: prefix) do
        add :id, :binary_id, primary_key: true
        add :slug, :string, size: 160, null: false
        add :categories, {:array, :string}, null: false, default: []
        add :segments, {:array, :string}, null: false, default: []
        add :published_at, :utc_datetime_usec
        add :announced_at, :utc_datetime_usec
        add :author, :map
        timestamps(type: :utc_datetime_usec)
      end

      create_if_not_exists unique_index(:tayori_entries, [:slug], prefix: prefix)
      create_if_not_exists index(:tayori_entries, [:published_at], prefix: prefix)

      create_if_not_exists table(:tayori_translations, primary_key: false, prefix: prefix) do
        add :id, :binary_id, primary_key: true

        add :entry_id,
            references(:tayori_entries, type: :binary_id, on_delete: :delete_all, prefix: prefix),
            null: false

        add :locale, :string, size: 35, null: false
        add :title, :string, size: 255, null: false
        add :summary, :text
        add :body, :map
        timestamps(type: :utc_datetime_usec)
      end

      create_if_not_exists unique_index(:tayori_translations, [:entry_id, :locale],
                             prefix: prefix
                           )

      create_if_not_exists table(:tayori_reads, primary_key: false, prefix: prefix) do
        add :reader, :string, size: 255, primary_key: true
        add :seen_at, :utc_datetime_usec, null: false
      end

      create_if_not_exists table(:tayori_settings, primary_key: false, prefix: prefix) do
        add :key, :string, size: 64, primary_key: true
        add :value, :map
        add :secret, :binary
        timestamps(type: :utc_datetime_usec)
      end
    end

    :ok
  end

  @doc "Drops the tables."
  @spec down(keyword()) :: :ok
  def down(opts \\ []) do
    prefix = opts[:prefix]
    drop_if_exists table(:tayori_settings, prefix: prefix)
    drop_if_exists table(:tayori_reads, prefix: prefix)
    drop_if_exists table(:tayori_translations, prefix: prefix)
    drop_if_exists table(:tayori_entries, prefix: prefix)
    :ok
  end
end
