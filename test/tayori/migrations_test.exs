defmodule Tayori.MigrationsTest do
  use ExUnit.Case

  alias PhoenixMountable.Migrations.Test, as: MigrationsTest

  # Every version up, down and up again, an upgrade from each, and the
  # columns a host adds kept: on a SQLite database of its own, and on
  # PostgreSQL in a schema of its own (the prefix).
  test "the migrations, on SQLite" do
    MigrationsTest.run_suite(TayoriTest.MigrationsRepo, Tayori.Migrations)
  end

  @tag :postgres
  test "the migrations, on PostgreSQL, in a prefix" do
    repo = TayoriTest.PostgresMigrationsRepo
    MigrationsTest.run_suite(repo, Tayori.Migrations, prefix: "tayori_migrations_test")
    repo.query!(~s(DROP SCHEMA IF EXISTS "tayori_migrations_test" CASCADE))
  end

  test "version 2 adds the campaigns' tables, and its down drops them" do
    repo = TayoriTest.MigrationsRepo
    MigrationsTest.reset!(repo)
    MigrationsTest.up(repo, Tayori.Migrations, version: 1)
    v1 = tables(repo)
    MigrationsTest.up(repo, Tayori.Migrations, version: 2)

    assert tables(repo) -- v1 == ~w(
             tayori_campaign_steps tayori_campaigns tayori_deliveries tayori_enrollments
             tayori_events tayori_letters tayori_segments tayori_suppressions
           )

    MigrationsTest.down(repo, Tayori.Migrations, to: 1)
    assert tables(repo) == v1
  end

  defp tables(repo) do
    %{rows: rows} =
      repo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'tayori_%' ORDER BY name"
      )

    List.flatten(rows)
  end
end
