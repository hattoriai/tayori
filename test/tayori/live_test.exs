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
end
