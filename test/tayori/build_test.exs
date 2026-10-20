defmodule Tayori.BuildTest do
  # The files of a real build (`mix test --include build`, after `mix
  # tayori.build`): CI's empty files are not a build.
  use ExUnit.Case, async: true

  @moduletag :build

  test "the pages serve the files of the build" do
    for {definition, name} <- [
          {Tayori.Router, :js},
          {Tayori.Router, :css},
          {Tayori.Router.Page, :css},
          {Tayori.Router.Page, :sumi}
        ] do
      body = definition.__phoenix_mountable_asset__(name, :identity)
      assert byte_size(body) > 1000, "#{inspect(definition)} #{name} is empty"
    end
  end
end
