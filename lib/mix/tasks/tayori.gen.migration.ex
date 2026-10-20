defmodule Mix.Tasks.Tayori.Gen.Migration do
  @shortdoc "Generates the migration that installs or upgrades Tayori's tables"

  @moduledoc """
  Generates the migration of Tayori's tables in the app's repo: the one
  that installs them, or, after an upgrade of Tayori, the one that brings
  them to its latest version.

      $ mix tayori.gen.migration
      $ mix tayori.gen.migration --repo MyApp.Repo

  It is `mix phoenix_mountable.gen.migration Tayori.Migrations`: the version
  the app is at is read from its migrations, and the new migration pins the
  latest (see `Tayori.Migrations`). Run it with `mix ecto.migrate`.

  The options are those of `mix phoenix_mountable.gen.migration`, such as
  `--repo` and `--migrations-path`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args), do: Mix.Task.run("phoenix_mountable.gen.migration", ["Tayori.Migrations" | args])
end
