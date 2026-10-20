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

    test "mark_seen tells the reader's other tabs" do
      reader = %Reader{id: "u2"}
      :ok = Tayori.subscribe(reader)
      :ok = Tayori.mark_seen(reader)
      assert_receive {Tayori, :seen, "u2"}
    end
  end
end
