defmodule Tayori.LiveTest do
  use TayoriTest.ConnCase

  defp as_reader(conn, reader), do: with_session(conn, %{"reader" => reader})

  test "a reader sees the count of what they have not seen", %{conn: conn} do
    entry!("One", %{published_at: minutes(-3)})
    entry!("Two", %{published_at: minutes(-2), segments: ["plan:pro"]})

    {:ok, _view, html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
    assert html =~ ~s(aria-label="What&#39;s new, 1 new update")
    assert html =~ ~s(<span class="tayori-badge" aria-hidden="true">)

    {:ok, _view, html} =
      conn |> as_reader(%{"id" => "u2", "segments" => ["plan:pro"]}) |> live("/")

    assert html =~ "2 new updates"
  end

  test "opening the panel shows the news, marks it seen, and pages", %{conn: conn} do
    for n <- 1..3, do: entry!("Entry #{n}", %{published_at: minutes(-10 + n)})
    {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")

    html = view |> element(".tayori-button") |> render_click()
    assert html =~ ~s(id="tayori-panel")
    assert html =~ "Entry 3"
    assert html =~ "Entry 2"
    refute html =~ "Entry 1"
    refute html =~ "tayori-badge"
    assert Tayori.unread_count(%Reader{id: "u1"}) == 0

    html = view |> element(".tayori-more") |> render_click()
    assert html =~ "Entry 1"
    refute html =~ "tayori-more"

    html = render_keydown(view, "tayori:close", %{"key" => "Escape"})
    refute html =~ ~s(id="tayori-panel")
  end

  test "the New mark is on what was published since the reader last looked", %{conn: conn} do
    entry!("Old", %{published_at: minutes(-30)})
    :ok = Tayori.mark_seen(%Reader{id: "u1"}, minutes(-20))
    entry!("Fresh", %{published_at: minutes(-1)})

    {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
    html = view |> element(".tayori-button") |> render_click()

    [fresh, old] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".tayori-card")
      |> Enum.map(&LazyHTML.text/1)

    assert fresh =~ "New" and fresh =~ "Fresh"
    refute old =~ "New"
  end

  test "a published entry reaches the open pages, and seeing in one tab clears the others", %{
    conn: conn
  } do
    conn = as_reader(conn, %{"id" => "u1"})
    {:ok, tab1, _html} = live(conn, "/")
    {:ok, tab2, _html} = live(conn, "/")

    entry = entry!("Live news")
    {:ok, _} = Entries.publish(entry)
    Tayori.broadcast({Tayori, :published, entry.id})

    assert render(tab1) =~ "1 new update"
    assert render(tab2) =~ "1 new update"

    tab1 |> element(".tayori-button") |> render_click()
    refute render(tab2) =~ "new update"
  end

  test "a visitor sees the news for everyone, in their language, and nothing is unread", %{
    conn: conn
  } do
    entry!("Exports", %{
      published_at: minutes(-1),
      translations: [%{locale: "en", title: "Exports"}, %{locale: "pt-PT", title: "Exportações"}]
    })

    entry!("Pro only", %{published_at: minutes(-1), segments: ["plan:pro"]})

    {:ok, view, html} = live(conn, "/")
    refute html =~ "tayori-badge"

    html = view |> element(".tayori-button") |> render_click()
    assert html =~ "Exports"
    refute html =~ "Pro only"

    {:ok, view, _html} = conn |> as_reader(%{"id" => "u9", "locale" => "pt-PT"}) |> live("/")
    html = view |> element(".tayori-button") |> render_click()
    assert html =~ "Novidades"
    assert html =~ "Exportações"
  end

  defp open(view), do: view |> element(".tayori-button") |> render_click()

  defp card_titles(view) do
    view |> Tayori.Test.entries() |> Enum.map(& &1.title)
  end

  describe "the panel" do
    test "filters by category, and All shows every entry again", %{conn: conn} do
      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "New", "pt-PT" => "Novo"}})
      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "Fixed"}})
      entry!("Shiny", %{published_at: minutes(-2), categories: ["new"]})
      entry!("Mended", %{published_at: minutes(-1), categories: ["fixed"]})

      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      open(view)
      assert card_titles(view) == ["Mended", "Shiny"]

      view |> element("#tayori-panel .tayori-chip", "New") |> render_click()
      assert card_titles(view) == ["Shiny"]
      assert has_element?(view, ~s(.tayori-chip[aria-pressed="true"]), "New")

      view |> element("#tayori-panel .tayori-chip", "All") |> render_click()
      assert card_titles(view) == ["Mended", "Shiny"]

      # A category renamed in the admin reaches the open panel.
      {:ok, _} =
        Tayori.Categories.update(Tayori.Categories.get("new"), %{"names" => %{"en" => "Fresh"}})

      assert has_element?(view, "#tayori-panel .tayori-chip", "Fresh")
    end

    test "opens an entry whole, and goes back to the list", %{conn: conn} do
      entry!("Exports", %{published_at: minutes(-2)})
      entry!("Boards", %{published_at: minutes(-1)})

      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      open(view)

      html = view |> element(".tayori-card-title button", "Exports") |> render_click()
      assert html =~ ~s(id="tayori-panel-entry")
      assert html =~ "About Exports."
      refute has_element?(view, "#tayori-panel-list")

      view |> element(~s(#tayori-panel button[phx-click="tayori:back"])) |> render_click()
      assert card_titles(view) == ["Boards", "Exports"]

      # Escape goes back from an entry, then closes.
      view |> element(".tayori-card-title button", "Boards") |> render_click()
      render_keydown(view, "tayori:back", %{"key" => "Escape"})
      assert has_element?(view, "#tayori-panel-list")
      assert :ok = Tayori.Test.close_news(view)
      refute has_element?(view, "#tayori-panel")
    end

    test "an entry the panel does not show is not opened", %{conn: conn} do
      pro = entry!("For pro", %{published_at: minutes(-1), segments: ["plan:pro"]})
      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      open(view)

      render_click(view, "tayori:show", %{"id" => pro.id})
      refute has_element?(view, "#tayori-panel-entry")
    end
  end

  describe "reactions" do
    setup %{config: config} do
      put_config(config, features: [:reactions])
      %{entry: entry!("Exports", %{published_at: minutes(-1)})}
    end

    test "a reader reacts, and the counts reach the other open panels", %{
      conn: conn,
      entry: entry
    } do
      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      {:ok, other, _html} = conn |> as_reader(%{"id" => "u2"}) |> live("/")
      open(other)
      open(view)
      view |> element(".tayori-card-title button", "Exports") |> render_click()

      view |> element(~s(.tayori-reaction[phx-value-emoji="🚀"])) |> render_click()

      assert has_element?(
               view,
               ~s(.tayori-reaction[aria-pressed="true"][phx-value-emoji="🚀"]),
               "1"
             )

      assert Tayori.Reactions.totals([entry.id]) == %{entry.id => 1}
      assert has_element?(other, ".tayori-reaction-counts", "🚀 1")

      view |> element(~s(.tayori-reaction[phx-value-emoji="🚀"])) |> render_click()
      refute has_element?(view, ~s(.tayori-reaction[aria-pressed="true"]))
      assert Tayori.Reactions.totals([entry.id]) == %{}
    end

    test "the cards keep their counts after an entry is opened and closed", %{
      conn: conn,
      entry: entry
    } do
      boards = entry!("Boards", %{published_at: minutes(-2)})
      {:ok, _} = Tayori.Reactions.toggle(%Reader{id: "u2"}, entry.id, "🎉")
      {:ok, _} = Tayori.Reactions.toggle(%Reader{id: "u2"}, boards.id, "👀")

      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      open(view)
      assert has_element?(view, "#tayori-entry-#{boards.id} .tayori-reaction-counts", "👀 1")

      view |> element(".tayori-card-title button", "Exports") |> render_click()
      view |> element(~s(#tayori-panel button[phx-click="tayori:back"])) |> render_click()

      assert has_element?(view, "#tayori-entry-#{entry.id} .tayori-reaction-counts", "🎉 1")
      assert has_element?(view, "#tayori-entry-#{boards.id} .tayori-reaction-counts", "👀 1")
    end

    test "a visitor sees the reactions and cannot react", %{conn: conn, entry: entry} do
      {:ok, _} = Tayori.Reactions.toggle(%Reader{id: "u1"}, entry.id, "🎉")
      {:ok, view, _html} = live(conn, "/")
      open(view)
      assert has_element?(view, ".tayori-reaction-counts", "🎉 1")
      view |> element(".tayori-card-title button", "Exports") |> render_click()
      assert has_element?(view, ".tayori-reaction[disabled]")

      render_click(view, "tayori:react", %{"id" => entry.id, "emoji" => "🚀"})
      assert Tayori.Reactions.totals([entry.id]) == %{entry.id => 1}
    end

    test "with the feature off, no reactions", %{conn: conn, config: config, entry: entry} do
      put_config(config, features: [])
      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      open(view)
      view |> element(".tayori-card-title button", "Exports") |> render_click()
      refute has_element?(view, ".tayori-reactions")

      render_click(view, "tayori:react", %{"id" => entry.id, "emoji" => "🚀"})
      assert Tayori.Reactions.totals([entry.id]) == %{}
    end
  end

  describe "announcements" do
    setup %{config: config} do
      put_config(config, features: [:announcements])
      :ok
    end

    defp announce!(title, kind, attrs \\ %{}) do
      entry!(title, Map.merge(%{published_at: minutes(-1), announce: kind}, attrs))
    end

    test "the newest announcement is shown, as its kind, until it is dismissed", %{conn: conn} do
      announce!("Older banner", "banner", %{published_at: minutes(-10)})

      announce!("Exports", "popup", %{
        translations: [
          %{
            locale: "en",
            title: "Exports",
            summary: "In two clicks",
            cta_label: "Export now",
            cta_url: "/exports"
          }
        ]
      })

      conn = as_reader(conn, %{"id" => "u1"})
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, ~s(#tayori-announcement.tayori-announcement-popup[role="dialog"]))
      assert has_element?(view, "#tayori-announcement-title", "Exports")
      assert has_element?(view, ".tayori-announcement-summary", "In two clicks")

      assert has_element?(
               view,
               ~s(#tayori-announcement a.tayori-cta[href="/exports"]),
               "Export now"
             )

      view |> element(".tayori-announcement-close") |> render_click()
      refute has_element?(view, "#tayori-announcement")

      # Dismissed on every device: the next page shows the one before.
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(
               view,
               ~s(#tayori-announcement.tayori-announcement-banner[role="status"])
             )

      assert has_element?(view, "#tayori-announcement-title", "Older banner")
    end

    test "a dismissal in one tab takes it off the others", %{conn: conn} do
      announce!("Exports", "toast")
      conn = as_reader(conn, %{"id" => "u1"})
      {:ok, tab1, _html} = live(conn, "/")
      {:ok, tab2, _html} = live(conn, "/")

      tab1 |> element(".tayori-announcement-close") |> render_click()
      refute has_element?(tab2, "#tayori-announcement")
    end

    test "a popup or a toast hides while the panel is open; a banner stays", %{conn: conn} do
      announce!("Toast", "toast")
      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")

      open(view)
      refute has_element?(view, "#tayori-announcement")
      Tayori.Test.close_news(view)
      assert has_element?(view, "#tayori-announcement", "Toast")

      entry = announce!("Banner", "banner")
      Tayori.broadcast({Tayori, :published, entry.id})
      open(view)
      assert has_element?(view, ".tayori-announcement-banner", "Banner")
    end

    test "Read more opens it in the panel, which is enough of an answer", %{conn: conn} do
      entry!("Plain", %{published_at: minutes(-5)})
      announce!("Exports", "popup")
      conn = as_reader(conn, %{"id" => "u1"})
      {:ok, view, _html} = live(conn, "/")

      view |> element("#tayori-announcement button.tayori-cta") |> render_click()
      assert has_element?(view, "#tayori-panel-entry", "About Exports.")
      refute has_element?(view, "#tayori-announcement")

      # Back to the list of the news.
      view |> element(~s(#tayori-panel button[phx-click="tayori:back"])) |> render_click()
      assert card_titles(view) == ["Exports", "Plain"]

      {:ok, view, _html} = live(conn, "/")
      refute has_element?(view, "#tayori-announcement")
    end

    test "a visitor sees it until the page closes it", %{conn: conn} do
      announce!("Exports", "toast")
      {:ok, view, _html} = live(conn, "/")
      view |> element(".tayori-announcement-close") |> render_click()
      refute has_element?(view, "#tayori-announcement")

      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#tayori-announcement")
    end

    test "an announcement published while the page is open shows at once", %{conn: conn} do
      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      refute has_element?(view, "#tayori-announcement")

      entry = announce!("Exports", "banner")
      Tayori.broadcast({Tayori, :published, entry.id})
      assert has_element?(view, "#tayori-announcement", "Exports")
    end

    test "with the feature off, none is shown", %{conn: conn, config: config} do
      put_config(config, features: [])
      announce!("Exports", "popup")
      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      refute has_element?(view, "#tayori-announcement")
    end
  end

  describe "analytics" do
    test "the entries read in the panel are counted as panel views", %{
      conn: conn,
      config: config,
      repo: repo
    } do
      exports = entry!("Exports", %{published_at: minutes(-1)})
      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      open(view)
      assert repo.all(Tayori.View) == []

      put_config(config, features: [:analytics])
      {:ok, view, _html} = conn |> as_reader(%{"id" => "u1"}) |> live("/")
      open(view)
      view |> element(".tayori-card-title button", "Exports") |> render_click()

      assert [%Tayori.View{reader: "u1", source: "panel", entry_id: id}] = repo.all(Tayori.View)
      assert id == exports.id

      {:ok, view, _html} = live(build_conn(), "/")
      open(view)
      assert Tayori.Views.totals([exports.id]) == %{exports.id => %{views: 3, readers: 1}}
    end
  end
end
