defmodule Tayori.Migrations do
  @moduledoc """
  The tables of Tayori, in a migration of the app.

      $ mix tayori.gen.migration

  writes a migration that pins the latest version:

      defmodule MyApp.Repo.Migrations.AddTayori do
        use Ecto.Migration

        def up, do: Tayori.Migrations.up(version: 1)
        def down, do: Tayori.Migrations.down(to: 0)
      end

  The versions are `PhoenixMountable.Migrations`: tracked in the app's
  database (per prefix), checked when the admin is first used, and run on
  PostgreSQL and on SQLite. A later version of Tayori that changes the
  tables has a version 2; `mix tayori.gen.migration` then writes the
  migration that upgrades.

  The tables (version 1):

    * `tayori_entries` - an entry of the news: its slug, categories, the
      segments of readers it is for, and when it is published (nil while it
      is a draft);
    * `tayori_translations` - the title, summary and body of an entry, one
      row for each language;
    * `tayori_reads` - for each reader, when they last saw the news;
    * `tayori_settings` - the settings of the admin, such as the AI model
      and its key, encrypted.

  `up/1` takes `:version` and `:prefix` (the schema of the tables, in
  PostgreSQL); `down/1` takes `:to` and `:prefix`.
  """

  use PhoenixMountable.Migrations,
    otp_app: :tayori,
    versions: [Tayori.Migrations.V1],
    gen_task: "tayori.gen.migration"
end
