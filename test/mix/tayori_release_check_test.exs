defmodule Mix.Tasks.Tayori.ReleaseCheckTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tayori.ReleaseCheck

  @files ~w(tayori.esm.js tayori.cjs.js tayori.css tayori-sumi.css tayori-admin.js tayori-admin.css)

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    static = Path.join(tmp_dir, "priv/static")
    File.mkdir_p!(static)
    for file <- @files, do: File.write!(Path.join(static, file), "built")
    package = Path.join(tmp_dir, "package.json")
    File.write!(package, ~s({"name": "tayori", "version": "1.2.3"}))
    %{static: static, package: package}
  end

  test "passes with the six built files and the same version", %{
    static: static,
    package: package
  } do
    assert ReleaseCheck.check(static, package, "1.2.3") == :ok
  end

  test "fails for another file or directory in priv/static", %{static: static, package: package} do
    File.mkdir_p!(Path.join(static, "chunks"))
    File.write!(Path.join(static, "chunks/picker.js"), "")
    File.write!(Path.join(static, "tayori.esm.js.map"), "{}")

    assert {:error, problems} = ReleaseCheck.check(static, package, "1.2.3")
    assert "#{static}/tayori.esm.js.map is not a bundle file" in problems
    assert "#{static}/chunks is not a bundle file" in problems
  end

  test "fails for a missing or an empty bundle file", %{static: static, package: package} do
    File.rm!(Path.join(static, "tayori.cjs.js"))
    File.write!(Path.join(static, "tayori.css"), "")

    assert {:error, problems} = ReleaseCheck.check(static, package, "1.2.3")
    assert "#{static}/tayori.cjs.js is missing" in problems
    assert "#{static}/tayori.css is empty" in problems
  end

  test "fails when there is no priv/static", %{tmp_dir: tmp_dir, package: package} do
    static = Path.join(tmp_dir, "none")
    assert {:error, problems} = ReleaseCheck.check(static, package, "1.2.3")
    assert length(problems) == length(@files)
  end

  test "fails when package.json has another version", %{static: static, package: package} do
    assert ReleaseCheck.check(static, package, "1.2.4") ==
             {:error, ["the version of #{package} is not 1.2.4"]}
  end

  test "the files of this repository have the same version" do
    root = Path.expand("../..", __DIR__)
    package = root |> Path.join("package.json") |> File.read!() |> JSON.decode!()
    assert package["version"] == Mix.Project.config()[:version]
  end
end
