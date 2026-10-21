defmodule Tayori.Migrations.V2 do
  @moduledoc false
  # The campaigns: segments, sequences and broadcasts, their steps and
  # letters, who is in a sequence, each letter sent, the events the app
  # tracks, and the addresses that are not written to. As in V1, every
  # table is made whatever the modules of the app (Tayori.Config): turning
  # campaigns on needs no migration.

  use PhoenixMountable.Migration, description: "Tayori's campaigns"

  def up(ctx) do
    create table(:tayori_segments, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :name, :string, size: 160, null: false
      add :description, :text
      add :condition, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:tayori_campaigns, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :name, :string, size: 160, null: false
      add :kind, :string, size: 16, null: false
      add :purpose, :string, size: 16, null: false, default: "product"
      add :status, :string, size: 16, null: false, default: "draft"
      add :trigger, :map
      add :audience, :map
      add :goal, :map
      add :min_gap_hours, :integer, null: false, default: 24
      add :max_days, :integer
      add :send_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :sent_at, :utc_datetime_usec
      add :from_name, :string, size: 160
      add :reply_to, :string, size: 320
      add :author, :map
      timestamps(type: :utc_datetime_usec)
    end

    create index(:tayori_campaigns, [:kind, :status], prefix: ctx.prefix)

    create table(:tayori_campaign_steps, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true

      add :campaign_id,
          references(:tayori_campaigns,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :position, :integer, null: false, default: 0
      # Minutes after the person entered; 0 for a broadcast's one step.
      add :wait, :integer, null: false, default: 0
      add :skip_if, :map
      timestamps(type: :utc_datetime_usec)
    end

    create index(:tayori_campaign_steps, [:campaign_id, :position], prefix: ctx.prefix)

    create table(:tayori_letters, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true

      add :step_id,
          references(:tayori_campaign_steps,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :locale, :string, size: 35, null: false
      add :subject, :string, size: 255, null: false
      add :preheader, :string, size: 255
      add :body, :map
      add :text, :text
      add :cta_label, :string, size: 80
      add :cta_url, :string, size: 2048
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tayori_letters, [:step_id, :locale], prefix: ctx.prefix)

    create table(:tayori_enrollments, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true

      add :campaign_id,
          references(:tayori_campaigns,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :person, :string, size: 255, null: false
      add :state, :string, size: 16, null: false, default: "active"
      add :reason, :string, size: 32
      add :entered_at, :utc_datetime_usec, null: false
      # The wait of the last step handled, in minutes: -1 at entry.
      add :cursor, :integer, null: false, default: -1
      add :next_at, :utc_datetime_usec
      add :last_sent_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tayori_enrollments, [:campaign_id, :person], prefix: ctx.prefix)
    create index(:tayori_enrollments, [:state, :next_at], prefix: ctx.prefix)

    create table(:tayori_deliveries, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true

      add :campaign_id,
          references(:tayori_campaigns,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :step_id,
          references(:tayori_campaign_steps,
            type: :binary_id,
            on_delete: :nilify_all,
            prefix: ctx.prefix
          )

      add :person, :string, size: 255, null: false
      add :email, :string, size: 320
      add :locale, :string, size: 35
      add :status, :string, size: 16, null: false, default: "queued"
      add :reason, :string, size: 64
      add :provider_id, :string, size: 255
      add :sent_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tayori_deliveries, [:campaign_id, :step_id, :person], prefix: ctx.prefix)
    create index(:tayori_deliveries, [:email], prefix: ctx.prefix)
    create index(:tayori_deliveries, [:provider_id], prefix: ctx.prefix)

    create table(:tayori_events, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :person, :string, size: 255, null: false
      add :name, :string, size: 64, null: false
      add :meta, :map
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:tayori_events, [:person, :name, :occurred_at], prefix: ctx.prefix)
    create index(:tayori_events, [:name, :occurred_at], prefix: ctx.prefix)
    create index(:tayori_events, [:occurred_at], prefix: ctx.prefix)

    # Lowercased, so that one address is one row for each purpose.
    create table(:tayori_suppressions, primary_key: false, prefix: ctx.prefix) do
      add :email, :string, size: 320, null: false, primary_key: true
      add :purpose, :string, size: 16, null: false, primary_key: true
      add :reason, :string, size: 16, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end
  end

  def down(ctx) do
    drop table(:tayori_suppressions, prefix: ctx.prefix)
    drop table(:tayori_events, prefix: ctx.prefix)
    drop table(:tayori_deliveries, prefix: ctx.prefix)
    drop table(:tayori_enrollments, prefix: ctx.prefix)
    drop table(:tayori_letters, prefix: ctx.prefix)
    drop table(:tayori_campaign_steps, prefix: ctx.prefix)
    drop table(:tayori_campaigns, prefix: ctx.prefix)
    drop table(:tayori_segments, prefix: ctx.prefix)
  end
end
