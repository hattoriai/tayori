defmodule Tayori.NewsTest do
  use TayoriTest.DataCase

  doctest Tayori
  doctest Tayori.Entry
  doctest Tayori.Reader
  doctest Tayori.Locales
  doctest Tayori.Messages

  for_each_repo do
    test "a reader sees the published entries, the newest first" do
      entry!("Draft")
      entry!("Scheduled", %{published_at: minutes(30)})
      entry!("Older", %{published_at: minutes(-60)})
      entry!("Newer", %{published_at: minutes(-5)})

      titles = for e <- Tayori.news(%Reader{id: "u1"}), do: e.translation.title
      assert titles == ["Newer", "Older"]
    end

    test "entries for segments show only to readers in one of them" do
      entry!("For all", %{published_at: minutes(-3)})
      entry!("For pro", %{published_at: minutes(-2), segments: ["plan:pro"]})
      entry!("For owners", %{published_at: minutes(-1), segments: ["role:owner", "role:admin"]})

      titles = fn reader -> for e <- Tayori.news(reader), do: e.translation.title end

      assert titles.(Reader.visitor()) == ["For all"]
      assert titles.(%Reader{id: "u", segments: ["plan:pro"]}) == ["For pro", "For all"]

      assert titles.(%Reader{id: "u", segments: ["role:admin", "plan:free"]}) == [
               "For owners",
               "For all"
             ]
    end

    test "pages with :before" do
      for n <- 1..5, do: entry!("E#{n}", %{published_at: minutes(-10 + n)})
      [_, second] = Tayori.news(Reader.visitor(), limit: 2)

      titles =
        for e <- Tayori.news(Reader.visitor(), limit: 2, before: second), do: e.translation.title

      assert titles == ["E3", "E2"]
    end

    test "each entry in the reader's language, else the first" do
      entry!("Exports", %{
        published_at: minutes(-1),
        translations: [
          %{locale: "en", title: "Exports"},
          %{locale: "pt-PT", title: "Exportações"}
        ]
      })

      entry!("Only English", %{published_at: minutes(-2)})

      titles = for e <- Tayori.news(Reader.visitor("pt-PT")), do: e.translation.title
      assert titles == ["Exportações", "Only English"]
    end

    test "an entry by its slug, if the reader sees it" do
      entry!("Faster search!", %{published_at: minutes(-1)})
      entry!("Pro only", %{published_at: minutes(-1), segments: ["plan:pro"]})

      assert %Entry{slug: "faster-search"} = Tayori.entry(Reader.visitor(), "faster-search")
      assert Tayori.entry(Reader.visitor(), "pro-only") == nil
      assert Tayori.entry(%Reader{id: "u", segments: ["plan:pro"]}, "pro-only")
    end

    test "unread: since the reader last saw the news, or since they joined" do
      reader = %Reader{id: "u1", since: minutes(-100)}
      entry!("Before joining", %{published_at: minutes(-200)})
      entry!("One", %{published_at: minutes(-50)})
      entry!("Two", %{published_at: minutes(-10)})

      assert Tayori.unread_count(reader) == 2
      assert Tayori.unread_count(Reader.visitor()) == 0

      :ok = Tayori.mark_seen(reader, minutes(-20))
      assert Tayori.unread_count(reader) == 1
      assert %DateTime{} = Tayori.seen_at(reader)

      :ok = Tayori.mark_seen(reader)
      assert Tayori.unread_count(reader) == 0
      assert Tayori.unread_count(reader, max: 1) == 0
    end

    test "the pinned entries come first, the last pinned first, only on the first page" do
      for n <- 1..4, do: entry!("E#{n}", %{published_at: minutes(-10 + n)})
      {:ok, _} = Entries.pin(Tayori.entry(Reader.visitor(), "e1"))
      {:ok, _} = Entries.pin(Tayori.entry(Reader.visitor(), "e2"))

      titles = fn opts ->
        for e <- Tayori.news(Reader.visitor(), opts), do: e.translation.title
      end

      # The limit is of the entries besides the pinned ones.
      assert titles.(limit: 1) == ["E2", "E1", "E4"]
      [_e2, _e1, e4] = Tayori.news(Reader.visitor(), limit: 1)
      assert titles.(limit: 5, before: e4) == ["E3"]
    end

    test "a pinned entry the reader does not see is not first" do
      entry!("For all", %{published_at: minutes(-2)})
      pro = entry!("For pro", %{published_at: minutes(-5), segments: ["plan:pro"]})
      {:ok, _} = Entries.pin(pro)

      assert [%{slug: "for-all"}] = Tayori.news(Reader.visitor())

      assert [%{slug: "for-pro"}, %{slug: "for-all"}] =
               Tayori.news(%Reader{id: "u", segments: ["plan:pro"]})
    end

    test "search: every word, in the title, the summary or the body, in any language" do
      entry!("Faster exports", %{published_at: minutes(-3)})

      entry!("Shared boards", %{
        published_at: minutes(-2),
        translations: [
          %{
            locale: "en",
            title: "Shared boards",
            summary: "Work together on a board",
            body: Kotoba.Content.from_markdown("Invite your team.")
          },
          %{locale: "pt-PT", title: "Quadros partilhados"}
        ]
      })

      entry!("Draft exports")
      entry!("100% uptime", %{published_at: minutes(-1)})
      entry!("snake_case names", %{published_at: minutes(-1)})

      search = fn words ->
        for e <- Tayori.news(Reader.visitor(), search: words), do: e.slug
      end

      assert search.("EXPORTS") == ["faster-exports"]
      assert search.("together") == ["shared-boards"]
      assert search.("invite TEAM") == ["shared-boards"]
      assert search.("partilhados") == ["shared-boards"]
      assert search.("board exports") == []
      assert search.("%") == ["100-uptime"]
      assert search.("_") == ["snake-case-names"]
      assert search.("  ") |> length() == 4
      assert search.(nil) |> length() == 4
    end

    test "a category: its entries only" do
      entry!("New one", %{published_at: minutes(-3), categories: ["new"]})
      entry!("Both", %{published_at: minutes(-2), categories: ["fixed", "new"]})
      entry!("Fixed one", %{published_at: minutes(-1), categories: ["fixed"]})
      entry!("None", %{published_at: minutes(-1)})

      category = fn key ->
        for e <- Tayori.news(Reader.visitor(), category: key), do: e.slug
      end

      assert category.("new") == ["both", "new-one"]
      assert category.("fixed") == ["fixed-one", "both"]
      assert category.("ne") == []
      assert category.("missing") == []
      assert length(category.("")) == 4
      assert length(category.(nil)) == 4

      assert [%{slug: "both"}] = Tayori.news(Reader.visitor(), category: "new", search: "both")
    end

    test "adjacent: the newer and the older entries the reader sees" do
      oldest = entry!("Oldest", %{published_at: minutes(-30)})
      entry!("Hidden", %{published_at: minutes(-25), segments: ["plan:pro"]})
      middle = entry!("Middle", %{published_at: minutes(-20)})
      entry!("A draft")
      entry!("Later", %{published_at: minutes(30)})
      newest = entry!("Newest", %{published_at: minutes(-10)})

      visitor = Reader.visitor()

      assert {%Entry{slug: "newest"}, %Entry{slug: "oldest"} = older} =
               Tayori.adjacent(visitor, middle)

      assert older.translation.title == "Oldest"
      assert {nil, %Entry{slug: "middle"}} = Tayori.adjacent(visitor, newest)
      assert {%Entry{slug: "middle"}, nil} = Tayori.adjacent(visitor, oldest)

      pro = %Reader{id: "u", segments: ["plan:pro"]}
      assert {%Entry{slug: "middle"}, %Entry{slug: "oldest"}} = Tayori.adjacent(pro, hidden(pro))
    end

    test "adjacent: entries published at the same time keep an order" do
      at = minutes(-5)
      a = entry!("A", %{published_at: at})
      b = entry!("B", %{published_at: at})
      [first, second] = Enum.sort_by([a, b], & &1.id, :desc)

      assert {nil, %Entry{id: id}} = Tayori.adjacent(Reader.visitor(), first)
      assert id == second.id
      assert {%Entry{id: id}, nil} = Tayori.adjacent(Reader.visitor(), second)
      assert id == first.id
    end

    test "mark_seen tells the reader's other tabs" do
      reader = %Reader{id: "u2"}
      :ok = Tayori.subscribe(reader)
      :ok = Tayori.mark_seen(reader)
      assert_receive {Tayori, :seen, "u2"}
    end
  end

  defp hidden(reader), do: Tayori.entry(reader, "hidden")
end
