defmodule Mix.Tasks.Tayori.Gen.MigrationTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tayori.Gen.Migration

  test "the migration calls Tayori.Migration" do
    source = Migration.migration(MyApp.Repo, nil)
    assert source =~ "defmodule MyApp.Repo.Migrations.AddTayori do"
    assert source =~ "def up, do: Tayori.Migration.up(version: 1)"

    assert Migration.migration(MyApp.Repo, "app") =~
             ~s{Tayori.Migration.down(version: 1, prefix: "app")}

    assert {_ast, []} = Code.string_to_quoted_with_comments!(source) |> then(&{&1, []})
  end
end
