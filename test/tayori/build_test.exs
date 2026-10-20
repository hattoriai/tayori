defmodule Tayori.BuildTest do
  # The files of a real build (`mix test --include build`, after `mix
  # tayori.build`): CI's empty files are not a build.
  use ExUnit.Case, async: true

  @moduletag :build

  test "the pages serve the files of the build" do
    for key <- [:admin_js, :admin_css, :page_css, :page_sumi_css] do
      assert Tayori.Assets.size(key) > 1000, "#{key} is empty"
    end
  end
end
