defmodule Mix.Tasks.Tayori.Gen.MigrationTest do
  use ExUnit.Case, async: true

  # The task is phoenix_mountable's generator with Tayori's migrations; its
  # own tests cover the files it writes. Here, that the migrations module
  # pins a version the generator can read.
  test "Tayori.Migrations has its versions, the latest first to install" do
    assert Tayori.Migrations.latest_version() == 2
  end
end
