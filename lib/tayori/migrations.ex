defmodule Tayori.Migrations do
  @moduledoc """
  The tables of Tayori, in a migration of the app.

      $ mix tayori.gen.migration

  writes a migration that pins the latest version:

      defmodule MyApp.Repo.Migrations.AddTayori do
        use Ecto.Migration

        def up, do: Tayori.Migrations.up(version: 2)
        def down, do: Tayori.Migrations.down(to: 0)
      end

  The versions are `PhoenixMountable.Migrations`: tracked in the app's
  database (per prefix), checked when the admin is first used, and run on
  PostgreSQL and on SQLite. A later version of Tayori that changes the
  tables has a new version; `mix tayori.gen.migration` then writes the
  migration that upgrades. The changelog runs on a database still at
  version 1, and logs that an upgrade is pending.

  The tables of the changelog (version 1):

    * `tayori_entries` - an entry of the news: its slug, categories, the
      segments of readers it is for, and when it is published (nil while it
      is a draft);
    * `tayori_translations` - the title, summary and body of an entry, one
      row for each language;
    * `tayori_reads` - for each reader, when they last saw the news;
    * `tayori_settings` - the settings of the admin, such as the AI model
      and its key, encrypted.

  The tables of the campaigns (version 2), made whatever the modules of
  the app:

    * `tayori_segments` - a saved condition on the app's people;
    * `tayori_campaigns` - a sequence or a broadcast: who it is for, its
      goal, its status;
    * `tayori_campaign_steps` - a letter of a campaign and when it goes;
    * `tayori_letters` - the subject and body of a step, one row for each
      language;
    * `tayori_enrollments` - a person in a sequence, and where they are in
      it;
    * `tayori_deliveries` - each letter to each person, once;
    * `tayori_events` - what the app tracks of its people
      (`Tayori.track/3`);
    * `tayori_suppressions` - the addresses that are not written to, for
      a purpose or for all.

  `up/1` takes `:version` and `:prefix` (the schema of the tables, in
  PostgreSQL); `down/1` takes `:to` and `:prefix`.
  """

  use PhoenixMountable.Migrations,
    otp_app: :tayori,
    versions: [Tayori.Migrations.V1, Tayori.Migrations.V2],
    compatible_with: 1,
    gen_task: "tayori.gen.migration"
end
