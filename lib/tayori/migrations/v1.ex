defmodule Tayori.Migrations.V1 do
  @moduledoc false
  # The entries, their translations, the readers' reads and the settings.

  use PhoenixMountable.Migration, description: "Entries, translations, reads and settings"

  def up(ctx) do
    create table(:tayori_entries, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, size: 160, null: false
      add :categories, {:array, :string}, null: false, default: []
      add :segments, {:array, :string}, null: false, default: []
      add :published_at, :utc_datetime_usec
      add :announced_at, :utc_datetime_usec
      add :author, :map
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tayori_entries, [:slug], prefix: ctx.prefix)
    create index(:tayori_entries, [:published_at], prefix: ctx.prefix)

    create table(:tayori_translations, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true

      add :entry_id,
          references(:tayori_entries,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :locale, :string, size: 35, null: false
      add :title, :string, size: 255, null: false
      add :summary, :text
      add :body, :map
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tayori_translations, [:entry_id, :locale], prefix: ctx.prefix)

    create table(:tayori_reads, primary_key: false, prefix: ctx.prefix) do
      add :reader, :string, size: 255, primary_key: true
      add :seen_at, :utc_datetime_usec, null: false
    end

    create table(:tayori_settings, primary_key: false, prefix: ctx.prefix) do
      add :key, :string, size: 64, primary_key: true
      add :value, :map
      add :secret, :binary
      timestamps(type: :utc_datetime_usec)
    end
  end

  def down(ctx) do
    drop table(:tayori_settings, prefix: ctx.prefix)
    drop table(:tayori_reads, prefix: ctx.prefix)
    drop table(:tayori_translations, prefix: ctx.prefix)
    drop table(:tayori_entries, prefix: ctx.prefix)
  end
end
