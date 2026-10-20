defmodule Tayori.SourcesTest do
  use ExUnit.Case, async: true

  alias Tayori.Sources.{Changelog, Fragments}

  @changelog """
  # Changelog

  ## [Unreleased]

  ### Added

  - Calendar view, soon.

  ## [1.4.0] - 2026-10-20

  ### Added

  - **Exports** in two clicks: zip a project. Then get a link by email.
  - Search inside PDFs,
    across every project. <!-- category: improved, highlight -->

  ### Fixed

  * Dates showed a day early in Auckland. <!-- audience: internal -->

  ## 1.3.0 - 2026-09-01

  ### Changed

  - Boards keep their columns' width.
  """

  describe "a Keep a Changelog file" do
    test "each item of each release is a change, with its version, kind and date" do
      [exports, search, dates, boards] = Changelog.parse(@changelog)

      assert exports.version == "1.4.0"
      assert exports.kind == "added"
      assert exports.title == "Exports in two clicks: zip a project"
      assert exports.body =~ "Then get a link by email."
      assert exports.occurred_at == ~U[2026-10-20 00:00:00Z]

      assert search.body == "Search inside PDFs,\nacross every project."
      assert search.category == "improved"
      assert search.highlight

      assert dates.kind == "fixed"
      assert dates.audience == "internal"

      assert boards.version == "1.3.0"
      assert boards.kind == "changed"
    end

    test "the unreleased section only when asked, and refs that stay the same" do
      refute Enum.any?(Changelog.parse(@changelog), &(&1.title =~ "Calendar"))

      assert [%{version: nil, title: "Calendar view, soon"} | _] =
               Changelog.parse(@changelog, :all)

      refs = Enum.map(Changelog.parse(@changelog), & &1.ref)
      assert refs == Enum.map(Changelog.parse(@changelog), & &1.ref)
      assert Enum.uniq(refs) == refs
      assert hd(refs) =~ ~r{^1\.4\.0/}
    end

    test "a file, by its path", %{} do
      dir = Path.join(System.tmp_dir!(), "tayori-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "CHANGELOG.md"), @changelog)

      assert {:ok, changes} = Changelog.changes(path: Path.join(dir, "CHANGELOG.md"))
      assert length(changes) == 4
      assert {:error, {:file, _, :enoent}} = Changelog.changes(path: Path.join(dir, "NOPE.md"))
    end
  end

  describe "fragments" do
    test "frontmatter, a body and its title" do
      change =
        Fragments.parse(
          """
          ---
          title: Exports in two clicks
          kind: added
          audience: public
          highlight: true
          segments: [plan:pro, plan:team]
          date: 2026-10-20
          ticket: ATL-12
          ---

          Zip a whole project, with its files.
          """,
          "exports.md"
        )

      assert change.ref == "exports.md"
      assert change.title == "Exports in two clicks"
      assert change.body == "Zip a whole project, with its files."
      assert change.kind == "added"
      assert change.highlight
      assert change.segments == ["plan:pro", "plan:team"]
      assert change.occurred_at == ~U[2026-10-20 00:00:00Z]
      assert change.meta == %{"ticket" => "ATL-12"}
    end

    test "no frontmatter: the title from the body; towncrier's kind from the name" do
      change = Fragments.parse("## Faster search\n\nResults as you type.\n", "1234.feature.md")
      assert change.title == "Faster search"
      assert change.kind == "feature"

      assert Fragments.parse("Fixed the dates.", "2.bugfix.md").kind == "bugfix"
      assert Fragments.parse("", "empty.md") == nil
    end

    test "a Changesets file" do
      change =
        Fragments.parse(
          """
          ---
          "@atelier/web": minor
          ---

          Add the timeline view.
          """,
          "brave-dogs-sing.md"
        )

      assert change.title == "Add the timeline view"
      assert change.meta == %{"@atelier/web" => "minor"}
      refute Map.has_key?(change, :kind)
    end

    test "a folder: its .md files, not its README" do
      dir = Path.join(System.tmp_dir!(), "tayori-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "old"))
      File.write!(Path.join(dir, "README.md"), "How to write a fragment.")
      File.write!(Path.join(dir, "a.md"), "Exports.")
      File.write!(Path.join(dir, "b.feature.md"), "Search.")
      File.write!(Path.join(dir, "old/c.md"), "Boards.")

      assert {:ok, changes} = Fragments.changes(path: dir)
      assert Enum.map(changes, & &1.ref) == ["a.md", "b.feature.md"]
      assert Enum.all?(changes, &match?(%DateTime{}, &1.occurred_at))

      assert {:ok, changes} = Fragments.changes(path: dir, recursive: true)
      assert "old/c.md" in Enum.map(changes, & &1.ref)

      assert {:error, {:folder, _, :enoent}} = Fragments.changes(path: Path.join(dir, "nope"))
    end
  end
end
