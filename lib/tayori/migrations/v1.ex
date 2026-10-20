defmodule Tayori.Migrations.V1 do
  @moduledoc false
  # The entries, their translations and categories, the readers' reads,
  # reactions, views and dismissals, the subscribers, and the settings.
  # Every table is made, whatever the features of the app (Tayori.Config):
  # turning a feature on needs no migration.

  use PhoenixMountable.Migration, description: "Tayori's tables"

  def up(ctx) do
    create table(:tayori_entries, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, size: 160, null: false
      add :categories, {:array, :string}, null: false, default: []
      add :segments, {:array, :string}, null: false, default: []
      add :cover, :map
      add :published_at, :utc_datetime_usec
      add :pinned_at, :utc_datetime_usec
      add :announce, :string, size: 16
      add :announce_until, :utc_datetime_usec
      add :announced_at, :utc_datetime_usec
      add :email, :boolean, null: false, default: false
      add :emailed_at, :utc_datetime_usec
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
      add :text, :text
      add :seo_title, :string, size: 255
      add :seo_description, :string, size: 500
      add :cta_label, :string, size: 80
      add :cta_url, :string, size: 2048
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tayori_translations, [:entry_id, :locale], prefix: ctx.prefix)

    create table(:tayori_categories, primary_key: false, prefix: ctx.prefix) do
      add :key, :string, size: 64, primary_key: true
      add :names, :map, null: false
      add :color, :string, size: 16, null: false
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create table(:tayori_reactions, primary_key: false, prefix: ctx.prefix) do
      add :entry_id,
          references(:tayori_entries,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false,
          primary_key: true

      add :reader, :string, size: 255, null: false, primary_key: true
      add :emoji, :string, size: 16, null: false, primary_key: true
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create table(:tayori_views, primary_key: false, prefix: ctx.prefix) do
      add :entry_id,
          references(:tayori_entries,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false,
          primary_key: true

      # A reader's id, or "" for the visitors of the day, counted together.
      add :reader, :string, size: 255, null: false, primary_key: true
      add :source, :string, size: 16, null: false, primary_key: true
      add :day, :date, null: false, primary_key: true
      add :count, :integer, null: false, default: 1
    end

    create index(:tayori_views, [:day], prefix: ctx.prefix)

    create table(:tayori_dismissals, primary_key: false, prefix: ctx.prefix) do
      add :reader, :string, size: 255, null: false, primary_key: true

      add :entry_id,
          references(:tayori_entries,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false,
          primary_key: true

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create table(:tayori_subscribers, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      # Lowercased, so that one address is one subscriber.
      add :email, :string, size: 320, null: false
      add :locale, :string, size: 35
      add :token, :string, size: 64, null: false
      add :confirmed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tayori_subscribers, [:email], prefix: ctx.prefix)
    create unique_index(:tayori_subscribers, [:token], prefix: ctx.prefix)

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

    # The inbox: the changes the app's sources bring (its CHANGELOG.md,
    # files of news, its CI, GitHub, its own code), before they become
    # an entry. A source's ref makes reading it again change nothing.
    create table(:tayori_changes, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :source, :string, size: 32, null: false
      add :ref, :string, size: 255, null: false
      add :title, :string, size: 255, null: false
      add :body, :text
      add :kind, :string, size: 32
      add :category, :string, size: 64
      add :audience, :string, size: 16, null: false, default: "public"
      add :segments, {:array, :string}, null: false, default: []
      add :highlight, :boolean, null: false, default: false
      add :version, :string, size: 64
      add :url, :string, size: 2048
      add :author, :string, size: 255
      add :occurred_at, :utc_datetime_usec, null: false
      add :state, :string, size: 16, null: false, default: "new"

      add :entry_id,
          references(:tayori_entries,
            type: :binary_id,
            on_delete: :nilify_all,
            prefix: ctx.prefix
          )

      add :meta, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tayori_changes, [:source, :ref], prefix: ctx.prefix)
    create index(:tayori_changes, [:state, :occurred_at], prefix: ctx.prefix)
    create index(:tayori_changes, [:entry_id], prefix: ctx.prefix)
  end

  def down(ctx) do
    drop table(:tayori_changes, prefix: ctx.prefix)
    drop table(:tayori_settings, prefix: ctx.prefix)
    drop table(:tayori_subscribers, prefix: ctx.prefix)
    drop table(:tayori_dismissals, prefix: ctx.prefix)
    drop table(:tayori_views, prefix: ctx.prefix)
    drop table(:tayori_reactions, prefix: ctx.prefix)
    drop table(:tayori_categories, prefix: ctx.prefix)
    drop table(:tayori_reads, prefix: ctx.prefix)
    drop table(:tayori_translations, prefix: ctx.prefix)
    drop table(:tayori_entries, prefix: ctx.prefix)
  end
end
