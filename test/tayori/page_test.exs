defmodule Tayori.PageTest do
  use TayoriTest.ConnCase

  test "the page lists the news for everyone, with Show more", %{conn: conn} do
    entry!("Hidden", %{published_at: minutes(-1), segments: ["plan:pro"]})
    for n <- 1..3, do: entry!("Entry #{n}", %{published_at: minutes(-10 + n)})

    html = conn |> get("/changelog") |> html_response(200)
    assert html =~ "<title>Test news</title>"
    assert html =~ "Entry 3"
    refute html =~ "Hidden"
    refute html =~ "Entry 1"
    assert html =~ ~s(href="/changelog?before=entry-2&amp;lang=en")
    assert html =~ ~r"/changelog/css-[0-9a-f]{32}"

    html = build_conn() |> get("/changelog?before=entry-2") |> html_response(200)
    assert html =~ "Entry 1"
  end

  test "one entry, in the reader's language", %{conn: conn} do
    entry!("Exports", %{
      published_at: minutes(-1),
      translations: [%{locale: "en", title: "Exports"}, %{locale: "pt-PT", title: "Exportações"}]
    })

    assert conn |> get("/changelog/exports") |> html_response(200) =~
             "<h1 class=\"tayori-entry-title\">"

    html = build_conn() |> get("/changelog/exports?lang=pt-PT") |> html_response(200)
    assert html =~ "Exportações"
    assert html =~ ~r{class="tayori-back">\s*<svg.*</svg>Test news}s
    assert html =~ Tayori.Messages.date(Tayori.Messages.for_locale("pt-PT"), Date.utc_today())

    assert build_conn() |> get("/changelog/nope") |> response(404)
  end

  test "the Atom feed and the JSON Feed", %{conn: conn} do
    entry!("Feed <me>", %{published_at: minutes(-1), categories: ["New"]})

    conn = get(conn, "/changelog/feed.xml")
    assert response_content_type(conn, :xml) =~ "application/atom+xml"
    xml = response(conn, 200)
    assert xml =~ "<title>Feed &lt;me&gt;</title>"
    assert xml =~ ~s(<link href="http://www.example.com/changelog/feed-me"/>)
    assert xml =~ ~s(<category term="New"/>)

    assert xml =~
             ~s(<content type="html">&lt;p&gt;About Feed &amp;lt;me&amp;gt;.&lt;/p&gt;</content>)

    feed = build_conn() |> get("/changelog/feed.json") |> response(200) |> JSON.decode!()
    assert feed["version"] == "https://jsonfeed.org/version/1.1"

    assert [%{"title" => "Feed <me>", "url" => "http://www.example.com/changelog/feed-me"}] =
             feed["items"]
  end
end
