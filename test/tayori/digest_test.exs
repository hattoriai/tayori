defmodule Tayori.DigestTest do
  use TayoriTest.DataCase

  alias Tayori.{Digest, Entry, Inbox}

  for_each_repo do
    test "nothing waiting, no entry" do
      assert Digest.run() == {:error, :nothing}
      {:ok, _} = Inbox.add(%{ref: "i", title: "Internal", audience: "internal"})
      assert Digest.run() == {:error, :nothing}
    end

    test "one change is an entry of its own, a draft" do
      {:ok, change} =
        Inbox.add(%{
          ref: "a",
          title: "Exports in two clicks",
          body: "Zip a **project**.",
          category: "new"
        })

      assert {:ok, %Entry{} = entry} = Digest.run()
      entry = Tayori.Entries.get!(entry.id)
      [t] = entry.translations

      assert Entry.status(entry) == :draft
      assert t.title == "Exports in two clicks"
      assert t.body.html =~ "<strong>project</strong>"
      assert entry.categories == ["new"]

      assert [%{state: "drafted", entry_id: id}] = Inbox.list()
      assert id == entry.id
      assert Inbox.get(change.id).state == "drafted"
      assert Digest.run() == {:error, :nothing}
    end

    test "several: grouped by category, the highlighted first, published when asked" do
      {:ok, _} =
        Tayori.Categories.create(%{
          "names" => %{"en" => "New"},
          "color" => "blue",
          "key" => "new"
        })

      {:ok, _} = Inbox.add(%{ref: "a", title: "Dates in Auckland", kind: "fixed"})

      {:ok, _} =
        Inbox.add(%{ref: "b", title: "Exports", body: "Exports. Zip it.", category: "new"})

      {:ok, _} = Inbox.add(%{ref: "c", title: "Timeline", category: "new", highlight: true})
      {:ok, _} = Inbox.add(%{ref: "d", title: "Refactor", audience: "internal"})

      assert {:ok, entry} = Digest.run(publish: :publish, now: ~U[2026-10-20 09:00:00Z])
      entry = Tayori.Entries.get!(entry.id)
      [t] = entry.translations

      assert Entry.status(entry) == :published
      assert t.title == "20 October 2026"
      assert t.body.text =~ ~r/New.*Timeline.*Exports: Zip it\..*Dates in Auckland/s
      refute t.body.text =~ "Refactor"
      assert Enum.sort(entry.categories) == ["new"]

      # The internal one is still waiting, for nothing.
      assert [%{ref: "d", state: "new"}] = Inbox.list(state: "new")
    end

    test "only the changes asked for, and the segments of an entry for some" do
      {:ok, a} = Inbox.add(%{ref: "a", title: "A", segments: ["plan:pro"]})
      {:ok, b} = Inbox.add(%{ref: "b", title: "B", segments: ["plan:team"]})
      {:ok, _c} = Inbox.add(%{ref: "c", title: "C"})

      assert {:ok, entry} = Digest.run(ids: [a.id, b.id])
      assert Enum.sort(entry.segments) == ["plan:pro", "plan:team"]
      assert [%{ref: "c"}] = Inbox.pending()

      assert {:ok, entry} = Digest.run()
      assert entry.segments == []
    end
  end
end
