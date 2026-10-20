defmodule Tayori.InboxTest do
  use TayoriTest.DataCase

  alias Tayori.{Change, Inbox}

  for_each_repo do
    test "a change is added once: the same source and ref is the same change" do
      assert {:ok, %Change{} = change} =
               Inbox.add(%{ref: "pr-1", title: "  Exports   in two clicks ", kind: "Added"})

      assert change.source == "app"
      assert change.title == "Exports in two clicks"
      assert change.kind == "added"
      assert change.audience == "public"
      assert change.state == "new"
      assert %DateTime{} = change.occurred_at

      assert {:ok, again} = Inbox.add(%{ref: "pr-1", title: "Something else"})
      assert again.id == change.id
      assert again.title == "Exports in two clicks"

      # Another source may use the same ref.
      assert {:ok, other} = Inbox.add(%{"ref" => "pr-1", "title" => "CI"}, source: "api")
      refute other.id == change.id
    end

    test "add_many counts the new, the known and the invalid" do
      {:ok, _} = Inbox.add(%{ref: "a", title: "A"})

      assert %{added: 1, existing: 1, errors: [{2, changeset}]} =
               Inbox.add_many([
                 %{ref: "a", title: "A"},
                 %{ref: "b", title: "B"},
                 %{ref: "c", title: "", url: "javascript:alert(1)"}
               ])

      assert %{title: ["can't be blank"], url: ["must be an http(s) address"]} =
               errors_on(changeset)
    end

    test "the category: given, else the kind's from the config, else the category named so",
         %{config: config} do
      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "Fixed"}, "color" => "red"})
      put_config(config, inbox: [kinds: %{"feature" => "new"}, audience: "internal"])

      {:ok, given} = Inbox.add(%{ref: "1", title: "A", kind: "feature", category: "api"})
      {:ok, mapped} = Inbox.add(%{ref: "2", title: "B", kind: "Feature"})
      {:ok, named} = Inbox.add(%{ref: "3", title: "C", kind: "fixed"})
      {:ok, none} = Inbox.add(%{ref: "4", title: "D", kind: "chore"})

      assert {given.category, mapped.category, named.category, none.category} ==
               {"api", "new", "fixed", nil}

      # The config's audience for a change that does not say.
      assert none.audience == "internal"
      assert {:ok, %{audience: "public"}} = Inbox.add(%{ref: "5", title: "E", audience: "public"})
    end

    test "the states: hidden, restored, drafted into an entry; pending is new and public" do
      {:ok, a} = Inbox.add(%{ref: "a", title: "A", occurred_at: minutes(-3)})
      {:ok, b} = Inbox.add(%{ref: "b", title: "B", occurred_at: minutes(-2), highlight: true})
      {:ok, c} = Inbox.add(%{ref: "c", title: "C", audience: "internal"})

      assert Enum.map(Inbox.pending(), & &1.id) == [b.id, a.id]

      {:ok, a} = Inbox.hide(a)
      assert a.state == "hidden"
      assert Enum.map(Inbox.pending(), & &1.id) == [b.id]

      {:ok, a} = Inbox.restore(a)
      assert a.state == "new"

      entry = entry!("Exports")
      assert Inbox.drafted([a.id, b.id], entry.id) == 2
      assert Inbox.pending() == []
      assert Enum.map(Inbox.list(entry_id: entry.id), & &1.ref) |> Enum.sort() == ["a", "b"]

      assert Inbox.counts() == %{"new" => 1, "drafted" => 2, "hidden" => 0}
      assert [%{id: id}] = Inbox.list(state: "new")
      assert id == c.id

      # The entry deleted, its changes stay, with no entry.
      {:ok, _} = Tayori.Entries.delete(entry)
      assert Enum.all?(Inbox.list(state: "drafted"), &is_nil(&1.entry_id))
    end

    test "update: what the admin changes of a change" do
      {:ok, change} = Inbox.add(%{ref: "a", title: "A"})
      :ok = Tayori.subscribe()

      assert {:ok, change} =
               Inbox.update(change, %{"audience" => "internal", "category" => "api", "ref" => "x"})

      assert change.audience == "internal"
      assert change.category == "api"
      assert change.ref == "a"
      assert_receive {Tayori, :inbox, id} when id == change.id

      assert {:error, changeset} = Inbox.update(change, %{"audience" => "everyone"})
      assert %{audience: ["is invalid"]} = errors_on(changeset)
      assert Inbox.get("nope") == nil
    end

    test "ingest reads every source, again and again", %{config: config} do
      dir = Path.join(System.tmp_dir!(), "tayori-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "news"))

      File.write!(
        Path.join(dir, "news/exports.md"),
        "---\nkind: added\n---\nExports in two clicks."
      )

      File.write!(Path.join(dir, "CHANGELOG.md"), """
      ## [1.0.0] - 2026-10-01

      ### Fixed

      - Dates in Auckland.
      """)

      put_config(config,
        inbox: [
          sources: [
            {Tayori.Sources.Fragments, path: Path.join(dir, "news")},
            {Tayori.Sources.Changelog, path: Path.join(dir, "CHANGELOG.md")},
            {Tayori.Sources.Changelog, path: Path.join(dir, "NOPE.md"), name: "missing"}
          ]
        ]
      )

      result = Inbox.ingest()
      assert {:ok, %{added: 1, existing: 0}} = result["fragments"]
      assert {:ok, %{added: 1}} = result["changelog"]
      assert {:error, {:file, _, :enoent}} = result["missing"]

      result = Inbox.ingest()
      assert {:ok, %{added: 0, existing: 1}} = result["fragments"]

      assert [%{source: "fragments", version: nil}, %{source: "changelog", version: "1.0.0"}] =
               Inbox.list()
    end
  end

  test "the inbox config is checked" do
    base = [repo: TayoriTest.SQLiteRepo, pubsub: TayoriTest.PubSub]

    assert Tayori.Config.new(base).inbox == %{
             sources: [],
             ingest_on_start: true,
             audience: "public",
             kinds: %{}
           }

    assert Tayori.Config.new(base).digest == %{
             every: :manual,
             at: ~T[09:00:00],
             publish: :draft,
             minimum: 1,
             translate: false
           }

    assert %{every: {:weekly, :monday}, publish: :publish} =
             Tayori.Config.new(base ++ [digest: [every: {:weekly, :monday}, publish: :publish]]).digest

    assert %{every: {:weekly, :monday}} =
             Tayori.Config.new(base ++ [digest: [every: :weekly]]).digest

    assert Tayori.Config.new(base).emails == %{every: :each, at: ~T[09:00:00]}

    assert Tayori.Config.new(base ++ [emails: [every: :monthly, at: ~T[08:30:00]]]).emails ==
             %{every: :monthly, at: ~T[08:30:00]}

    assert %{every: {:weekly, :friday}} =
             Tayori.Config.new(base ++ [emails: [every: {:weekly, :friday}]]).emails

    for bad <- [
          [inbox: [sources: [Enum]]],
          [inbox: [audience: "everyone"]],
          [inbox: [kinds: %{added: "new"}]],
          [digest: [every: :hourly]],
          [digest: [every: {:weekly, :someday}]],
          [digest: [publish: :now]],
          [digest: [minimum: 0]],
          [digest: [translate: "yes"]],
          [emails: [every: :ingest]],
          [emails: [every: {:days, 0}]],
          [emails: [at: "09:00"]],
          [emails: :weekly]
        ] do
      assert_raise ArgumentError, fn -> Tayori.Config.new(base ++ bad) end
    end
  end
end
