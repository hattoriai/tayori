defmodule Tayori.PageTest do
  use TayoriTest.ConnCase

  import Swoosh.TestAssertions

  alias Tayori.{Categories, Reactions, Subscribers, View}

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

  describe "in the app's layout" do
    test "the layout gets the page, its language and its tags", %{conn: conn} do
      entry!("Exports", %{published_at: minutes(-1), summary: "Exports, one click away."})

      html = conn |> get("/app-news") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert html =~ "<title>App news · The app</title>"
      assert attribute(doc, "html", "lang") == ["en"]
      assert attribute(doc, "link[rel=canonical]", "href") == ["http://www.example.com/app-news"]
      assert attribute(doc, "meta[name=description]", "content") == ["What we ship."]
      assert attribute(doc, "main", "data-description") == ["What we ship."]
      assert attribute(doc, "main", "data-feed") == ["/app-news/feed.xml"]

      assert attribute(doc, "link[type='application/atom+xml']", "href") == [
               "/app-news/feed.xml"
             ]

      assert text(LazyHTML.query(doc, ".app-header")) == "The app"
      assert text(LazyHTML.query(doc, "main .tayori-page-title")) == "App news"
      assert titles(doc) == ["Exports"]
      refute html =~ ~r"/app-news/css-"
    end

    test "an entry's JSON-LD goes in the layout's head", %{conn: conn} do
      entry!("Exports", %{published_at: minutes(-1)})

      doc = page(conn, "/app-news/exports")

      assert [json] =
               doc
               |> LazyHTML.query("head script[type='application/ld+json']")
               |> Enum.map(&LazyHTML.text/1)

      assert %{"@type" => "BlogPosting", "headline" => "Exports"} = JSON.decode!(json)

      assert attribute(doc, "link[rel=canonical]", "href") == [
               "http://www.example.com/app-news/exports"
             ]
    end

    test "the title and the description in the reader's language", %{conn: conn} do
      doc = page(conn, "/app-news?lang=pt-PT")

      assert attribute(doc, "html", "lang") == ["pt-PT"]
      assert text(LazyHTML.query(doc, ".tayori-page-title")) == "Novidades da app"
      # "pt" is the description of every Portuguese.
      assert text(LazyHTML.query(doc, ".tayori-page-description")) == "O que fazemos."

      feed = build_conn() |> get("/app-news/feed.json?lang=pt-PT") |> response(200)

      assert %{"title" => "Novidades da app", "description" => "O que fazemos."} =
               JSON.decode!(feed)
    end
  end

  test "a visitor gets the app's language, unless ?lang= says another", %{conn: conn} do
    conn = with_session(conn, %{"locale" => "pt_PT"})
    assert conn |> page("/news") |> attribute("html", "lang") == ["pt-PT"]
    assert conn |> page("/news?lang=en") |> attribute("html", "lang") == ["en"]

    # The page without the resolver does not ask the app.
    assert conn |> page("/changelog") |> attribute("html", "lang") == ["en"]
  end

  test "localized/2 picks the locale, its language, then the app's first" do
    texts = %{"en" => "News", "pt-PT" => "Novidades"}

    assert Tayori.Page.localized("News", "pt-PT") == "News"
    assert Tayori.Page.localized(nil, "en") == nil
    assert Tayori.Page.localized(texts, "pt-PT") == "Novidades"
    assert Tayori.Page.localized(texts, "pt-BR") == "Novidades"
    assert Tayori.Page.localized(texts, "en-GB") == "News"
    assert Tayori.Page.localized(texts, "ja") == "News"
  end

  defp as_reader(conn, reader), do: with_session(conn, %{"reader" => reader})

  defp page(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

  defp titles(html) do
    html |> LazyHTML.query(".tayori-timeline .tayori-entry-title") |> Enum.map(&text/1)
  end

  defp text(node), do: node |> LazyHTML.text() |> String.trim()

  defp attribute(html, selector, name) do
    html |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  end

  defp category!(name) do
    {:ok, category} = Categories.create(%{"names" => %{"en" => name}})
    category
  end

  describe "the list" do
    test "a category filters it; an unknown one shows all", %{conn: conn} do
      category!("New")
      category!("Fixed")
      entry!("Shiny", %{published_at: minutes(-2), categories: ["new"]})
      entry!("Mended", %{published_at: minutes(-1), categories: ["fixed"]})

      html = page(conn, "/changelog?category=new")
      assert titles(html) == ["Shiny"]

      assert html |> LazyHTML.query(~s(.tayori-chip[aria-current="page"])) |> text() == "New"
      assert attribute(html, ~s(meta[name="robots"]), "content") == ["noindex"]
      assert attribute(html, ~s(.tayori-search input[name="category"]), "value") == ["new"]

      html = page(build_conn(), "/changelog?category=nope")
      assert titles(html) == ["Mended", "Shiny"]
      assert attribute(html, ~s(meta[name="robots"]), "content") == []
      assert html |> LazyHTML.query(~s(.tayori-chip[aria-current="page"])) |> text() == "All"
    end

    test "a search finds the entries with every word, and says when none does", %{conn: conn} do
      entry!("Faster exports", %{published_at: minutes(-2)})
      entry!("Shared boards", %{published_at: minutes(-1)})

      html = page(conn, "/changelog?q=EXPORTS")
      assert titles(html) == ["Faster exports"]
      assert attribute(html, "#tayori-q", "value") == ["EXPORTS"]
      assert attribute(html, ~s(meta[name="robots"]), "content") == ["noindex"]
      assert html |> LazyHTML.query(".tayori-results a") |> text() == "Clear the search"

      html = page(build_conn(), "/changelog?q=faster+boards")
      assert titles(html) == []
      assert html |> LazyHTML.query(".tayori-results") |> text() =~ "Nothing matches your search."
      assert html |> LazyHTML.query(".tayori-empty") |> Enum.count() == 0

      html = page(build_conn(), "/changelog?q=+++")
      assert titles(html) == ["Shared boards", "Faster exports"]
    end

    test "the pinned entries come first on the first page only", %{conn: conn} do
      old = entry!("Old pinned", %{published_at: minutes(-60)})
      {:ok, _} = Entries.pin(old)
      for n <- 1..3, do: entry!("Entry #{n}", %{published_at: minutes(-10 + n)})

      html = page(conn, "/changelog")
      assert titles(html) == ["Old pinned", "Entry 3", "Entry 2"]

      assert attribute(html, ~s(a[rel="next"]), "href") == [
               "/changelog?before=entry-2&lang=en"
             ]

      html = page(build_conn(), "/changelog?before=entry-2")
      assert titles(html) == ["Entry 1"]
      assert attribute(html, ~s(a[rel="prev"]), "href") == ["/changelog?lang=en"]
      assert attribute(html, ~s(a[rel="next"]), "href") == []
    end

    test "the next page keeps the category and the search", %{conn: conn} do
      category!("New")

      for n <- 1..3,
          do: entry!("New #{n}", %{published_at: minutes(-10 + n), categories: ["new"]})

      entry!("Other", %{published_at: minutes(-1)})

      html = page(conn, "/changelog?category=new&q=new")
      assert titles(html) == ["New 3", "New 2"]

      [next] = attribute(html, ~s(a[rel="next"]), "href")

      assert URI.decode_query(URI.parse(next).query) == %{
               "before" => "new-2",
               "category" => "new",
               "q" => "new",
               "lang" => "en"
             }

      assert titles(page(build_conn(), next)) == ["New 1"]
    end

    test "a reader of the app sees their entries too", %{conn: conn} do
      entry!("For all", %{published_at: minutes(-2)})
      entry!("For pro", %{published_at: minutes(-1), segments: ["plan:pro"]})

      assert titles(page(conn, "/news")) == ["For all"]

      reader = %{"id" => "u1", "segments" => ["plan:pro"]}
      assert titles(page(as_reader(conn, reader), "/news")) == ["For pro", "For all"]
      assert titles(page(as_reader(conn, reader), "/changelog")) == ["For all"]
    end
  end

  describe "an entry" do
    test "links to the older and the newer entries", %{conn: conn} do
      entry!("First", %{published_at: minutes(-30)})
      entry!("Second", %{published_at: minutes(-20)})
      entry!("Third", %{published_at: minutes(-10)})

      html = page(conn, "/changelog/second")
      assert attribute(html, ~s(.tayori-entry-nav a[rel="prev"]), "href") == ["/changelog/first"]

      assert html |> LazyHTML.query(~s(.tayori-entry-nav a[rel="prev"] strong)) |> text() ==
               "First"

      assert attribute(html, ~s(.tayori-entry-nav a[rel="next"]), "href") == ["/changelog/third"]

      html = page(build_conn(), "/changelog/third")
      assert attribute(html, ~s(.tayori-entry-nav a[rel="next"]), "href") == []
      assert attribute(html, ~s(.tayori-entry-nav a[rel="prev"]), "href") == ["/changelog/second"]
    end

    test "has the tags of search engines and shared links", %{conn: conn} do
      {:ok, entry} =
        Entries.create(
          %{
            translations: [
              %{
                locale: "en",
                title: "Exports",
                summary: "In two clicks",
                seo_title: "Exports </script> in Atelier",
                body: Kotoba.Content.from_markdown("About exports.")
              },
              %{locale: "pt-PT", title: "Exportações"}
            ]
          },
          author: %{"id" => 7, "name" => "Hanzo"}
        )

      {:ok, entry} = Entries.publish(entry, minutes(-1))

      {:ok, _} =
        Entries.put_cover_map(entry, %{"url" => "/uploads/cover.png", "alt" => "A chart"})

      html = conn |> get("/changelog/exports") |> html_response(200)
      doc = LazyHTML.from_document(html)
      meta = fn selector -> doc |> LazyHTML.query(selector) |> LazyHTML.attribute("content") end
      url = "http://www.example.com/changelog/exports"

      assert doc |> LazyHTML.query("title") |> text() == "Exports </script> in Atelier"
      assert meta.(~s(meta[property="og:title"])) == ["Exports </script> in Atelier"]
      assert meta.(~s(meta[name="description"])) == ["In two clicks"]
      assert meta.(~s(meta[property="og:type"])) == ["article"]
      assert meta.(~s(meta[property="og:url"])) == [url]
      assert meta.(~s(meta[property="og:image"])) == ["http://www.example.com/uploads/cover.png"]
      assert meta.(~s(meta[property="og:image:alt"])) == ["A chart"]
      assert meta.(~s(meta[name="twitter:card"])) == ["summary_large_image"]
      assert meta.(~s(meta[name="robots"])) == []
      assert attribute(doc, ~s(link[rel="canonical"]), "href") == [url]

      assert attribute(doc, ~s(link[hreflang]), "href") == [
               url <> "?lang=en",
               url <> "?lang=pt-PT"
             ]

      # The JSON-LD cannot end its script early.
      [script] =
        Regex.run(~r{<script type="application/ld\+json">(.*?)</script>}s, html,
          capture: :all_but_first
        )

      refute script =~ "</"

      assert %{
               "@type" => "BlogPosting",
               "headline" => "Exports",
               "description" => "In two clicks",
               "url" => ^url,
               "image" => "http://www.example.com/uploads/cover.png",
               "inLanguage" => "en",
               "author" => %{"@type" => "Person", "name" => "Hanzo"}
             } = JSON.decode!(script)
    end

    test "with no cover, the picture is the body's first image, else the page's", %{conn: conn} do
      entry!("Pictured", %{
        published_at: minutes(-1),
        translations: [
          %{
            locale: "en",
            title: "Pictured",
            body: Kotoba.Content.from_markdown("![A board](/uploads/board.png)")
          }
        ]
      })

      entry!("Plain", %{published_at: minutes(-2)})

      og_image = fn conn, path ->
        conn |> page(path) |> attribute(~s(meta[property="og:image"]), "content")
      end

      assert og_image.(conn, "/changelog/pictured") == [
               "http://www.example.com/uploads/board.png"
             ]

      assert og_image.(build_conn(), "/changelog/plain") == []
      assert og_image.(build_conn(), "/news/plain") == ["https://cdn.test/news.png"]
    end

    test "an entry for some readers is only theirs", %{conn: conn} do
      entry!("For pro", %{published_at: minutes(-1), segments: ["plan:pro"]})

      assert conn |> get("/changelog/for-pro") |> response(404)
      assert build_conn() |> get("/news/for-pro") |> response(404)

      assert build_conn()
             |> as_reader(%{"id" => "u1", "segments" => ["plan:pro"]})
             |> get("/news/for-pro")
             |> html_response(200) =~ "For pro"
    end

    test "a view is counted from the page or from an email, with :analytics", %{
      conn: conn,
      config: config,
      repo: repo
    } do
      entry = entry!("Exports", %{published_at: minutes(-1)})

      conn |> get("/changelog/exports") |> html_response(200)
      assert repo.all(View) == []

      put_config(config, features: [:analytics])
      build_conn() |> get("/changelog/exports") |> html_response(200)
      build_conn() |> get("/changelog/exports?ref=email") |> html_response(200)
      build_conn() |> as_reader(%{"id" => "u1"}) |> get("/news/exports") |> html_response(200)
      build_conn() |> get("/changelog") |> html_response(200)

      assert repo.all(View) |> Enum.map(&{&1.reader, &1.source, &1.count}) |> Enum.sort() ==
               [{"", "email", 1}, {"", "page", 1}, {"u1", "page", 1}]

      assert Tayori.Views.totals([entry.id]) == %{entry.id => %{views: 3, readers: 1}}
    end
  end

  describe "a preview" do
    test "shows a draft with a valid link, never indexed", %{conn: conn} do
      draft = entry!("Not yet")
      token = Tayori.Page.preview_token(@endpoint, draft.id)

      assert conn |> get("/changelog/not-yet") |> response(404)

      html = build_conn() |> get("/changelog/preview/" <> token) |> html_response(200)
      doc = LazyHTML.from_document(html)
      assert doc |> LazyHTML.query(".tayori-entry-title") |> text() == "Not yet"
      assert doc |> LazyHTML.query(".tayori-preview-bar") |> text() =~ "not published yet"
      assert attribute(doc, ~s(meta[name="robots"]), "content") == ["noindex"]
    end

    test "an expired, a changed or a deleted entry's link is a 404", %{conn: conn} do
      draft = entry!("Not yet")
      week_ago = System.system_time(:second) - 8 * 24 * 3600

      expired =
        Phoenix.Token.sign(@endpoint, "tayori preview", draft.id, signed_at: week_ago)

      assert conn |> get("/changelog/preview/" <> expired) |> response(404)

      token = Tayori.Page.preview_token(@endpoint, draft.id)
      assert build_conn() |> get("/changelog/preview/" <> token <> "x") |> response(404)
      assert build_conn() |> get("/changelog/preview/nonsense") |> response(404)

      not_an_id = Tayori.Page.preview_token(@endpoint, "not-an-id")
      assert build_conn() |> get("/changelog/preview/" <> not_an_id) |> response(404)

      {:ok, _} = Entries.delete(draft)
      assert build_conn() |> get("/changelog/preview/" <> token) |> response(404)
    end
  end

  describe "reactions" do
    setup %{config: config} do
      put_config(config, features: [:reactions])
      %{entry: entry!("Exports", %{published_at: minutes(-1)})}
    end

    test "a reader reacts with a form, and goes back where they were", %{conn: conn, entry: entry} do
      conn = as_reader(conn, %{"id" => "u1"})

      html = page(conn, "/news/exports")
      buttons = LazyHTML.query(html, ".tayori-reactions button")
      assert Enum.count(buttons) == 5
      assert LazyHTML.attribute(buttons, "disabled") == []
      assert attribute(html, ".tayori-reactions", "action") == ["/news/exports/react"]

      sent =
        post(conn, "/news/exports/react", %{"emoji" => "🚀", "return" => "/news#entry-exports"})

      assert redirected_to(sent, 303) == "/news#entry-exports"
      assert {%{} = counts, %{} = mine} = Reactions.for_entries(%Reader{id: "u1"}, [entry.id])
      assert counts == %{entry.id => %{"🚀" => 1}}
      assert mine == %{entry.id => ["🚀"]}

      html = page(conn, "/news")

      pressed = LazyHTML.query(html, ~s(.tayori-reaction[aria-pressed="true"]))
      assert LazyHTML.attribute(pressed, "value") == ["🚀"]

      assert html
             |> LazyHTML.query(~s(.tayori-reaction[aria-pressed="true"] .tayori-reaction-count))
             |> text() == "1"

      # Again, off; a return elsewhere goes to the entry.
      sent = post(conn, "/news/exports/react", %{"emoji" => "🚀", "return" => "https://evil.test"})
      assert redirected_to(sent, 303) == "/news/exports"
      assert Reactions.totals([entry.id]) == %{}

      sent = post(conn, "/news/exports/react", %{"emoji" => "🚀", "return" => "//evil.test/news"})
      assert redirected_to(sent, 303) == "/news/exports"

      # An emoji that is not the app's is nothing.
      post(conn, "/news/exports/react", %{"emoji" => "💩"})
      assert Reactions.totals([entry.id]) == %{entry.id => 1}
    end

    test "a visitor sees the counts and cannot react", %{conn: conn, entry: entry} do
      {:ok, _} = Reactions.toggle(%Reader{id: "u1"}, entry.id, "🎉")

      html = page(conn, "/changelog/exports")
      buttons = LazyHTML.query(html, ".tayori-reactions button")
      assert Enum.count(LazyHTML.attribute(buttons, "disabled")) == 5
      assert html |> LazyHTML.query(".tayori-reaction-count") |> text() == "1"

      sent = post(build_conn(), "/changelog/exports/react", %{"emoji" => "🚀"})
      assert redirected_to(sent, 303) == "/changelog"
      assert Reactions.totals([entry.id]) == %{entry.id => 1}
    end

    test "a reader cannot react to an entry they do not see", %{conn: conn} do
      pro = entry!("For pro", %{published_at: minutes(-1), segments: ["plan:pro"]})

      sent = conn |> as_reader(%{"id" => "u1"}) |> post("/news/for-pro/react", %{"emoji" => "🚀"})
      assert redirected_to(sent, 303) == "/news"
      assert Reactions.totals([pro.id]) == %{}
    end

    test "with the feature off, no form and no route", %{conn: conn, config: config, entry: entry} do
      put_config(config, features: [])
      conn = as_reader(conn, %{"id" => "u1"})

      html = page(conn, "/news/exports")
      assert html |> LazyHTML.query(".tayori-reactions") |> Enum.count() == 0
      assert page(conn, "/news") |> LazyHTML.query(".tayori-reactions") |> Enum.count() == 0

      assert conn |> post("/news/exports/react", %{"emoji" => "🚀"}) |> response(404)
      assert Reactions.totals([entry.id]) == %{}
    end
  end

  describe "subscriptions" do
    setup %{config: config} do
      config =
        put_config(config,
          features: [:subscriptions],
          mailer: TayoriTest.Mailer,
          email_from: {"Atelier", "news@atelier.test"},
          page_url: "https://atelier.test/changelog"
        )

      %{config: config}
    end

    defp subscriber(repo, email), do: repo.get_by(Subscribers, email: email)

    test "the page and each entry have the form", %{conn: conn} do
      entry!("Exports", %{published_at: minutes(-1)})

      html = page(conn, "/changelog")
      assert attribute(html, "#subscribe-form", "action") == ["/changelog/subscribe"]
      assert attribute(html, ~s(#subscribe-form input[name="_csrf_token"]), "value") != [""]

      html = page(build_conn(), "/changelog/exports")
      assert html |> LazyHTML.query("#subscribe #subscribe-form") |> Enum.count() == 1
    end

    test "subscribing sends a link in the reader's language, and says so", %{
      conn: conn,
      repo: repo
    } do
      sent =
        conn
        |> put_req_header("accept-language", "pt-PT,pt;q=0.9")
        |> post("/changelog/subscribe", %{"email" => "Ada@Example.com"})

      assert redirected_to(sent, 303) == "/changelog?notice=subscribed#subscribe"
      assert %{locale: "pt-PT", confirmed_at: nil} = subscriber(repo, "ada@example.com")
      assert_email_sent(subject: "Confirme a sua subscrição")

      html = page(build_conn(), "/changelog?notice=subscribed")
      assert html |> LazyHTML.query(".tayori-notice") |> text() =~ "check your inbox"

      sent = post(build_conn(), "/changelog/subscribe", %{"email" => "nope"})
      assert redirected_to(sent, 303) == "/changelog?notice=invalid_email#subscribe"
      html = page(build_conn(), "/changelog?notice=invalid_email")
      assert html |> LazyHTML.query(".tayori-notice-error") |> text() =~ "Email address?"

      # A notice the page does not know is none.
      html = page(build_conn(), "/changelog?notice=<script>")
      assert html |> LazyHTML.query(".tayori-notice") |> Enum.count() == 0
    end

    test "the link of the email confirms, and an unknown one says it does not work", %{
      conn: conn,
      repo: repo
    } do
      :ok = Subscribers.subscribe("ada@example.com")
      %{token: token} = subscriber(repo, "ada@example.com")

      sent = get(conn, "/changelog/subscription/confirm/" <> token)
      assert redirected_to(sent, 303) == "/changelog?notice=confirmed"
      assert %{confirmed_at: %DateTime{}} = subscriber(repo, "ada@example.com")

      sent = get(build_conn(), "/changelog/subscription/confirm/nope")
      assert redirected_to(sent, 303) == "/changelog?notice=invalid"
      html = page(build_conn(), "/changelog?notice=invalid")
      assert html |> LazyHTML.query(".tayori-notice-error") |> text() =~ "does not work"
    end

    test "unsubscribing: a link, or the one click of an email client", %{conn: conn, repo: repo} do
      for email <- ~w(a@x.io b@x.io), do: :ok = Subscribers.subscribe(email)
      %{token: a} = subscriber(repo, "a@x.io")
      %{token: b} = subscriber(repo, "b@x.io")

      sent = get(conn, "/changelog/subscription/unsubscribe/" <> a)
      assert redirected_to(sent, 303) == "/changelog?notice=unsubscribed"
      assert subscriber(repo, "a@x.io") == nil

      sent =
        post(build_conn(), "/changelog/subscription/unsubscribe/" <> b, %{
          "List-Unsubscribe" => "One-Click"
        })

      assert response(sent, 200) == ""
      assert subscriber(repo, "b@x.io") == nil
    end

    test "with the feature off, no form and no route", %{conn: conn, config: config, repo: repo} do
      :ok = Subscribers.subscribe("ada@example.com")
      %{token: token} = subscriber(repo, "ada@example.com")
      put_config(config, features: [])
      entry!("Exports", %{published_at: minutes(-1)})

      assert page(conn, "/changelog") |> LazyHTML.query("#subscribe-form") |> Enum.count() == 0

      assert page(build_conn(), "/changelog/exports")
             |> LazyHTML.query("#subscribe")
             |> Enum.count() == 0

      assert build_conn() |> post("/changelog/subscribe", %{"email" => "b@x.io"}) |> response(404)
      assert build_conn() |> get("/changelog/subscription/confirm/" <> token) |> response(404)
      assert build_conn() |> get("/changelog/subscription/unsubscribe/" <> token) |> response(404)

      assert build_conn()
             |> post("/changelog/subscription/unsubscribe/" <> token)
             |> response(404)

      assert %{confirmed_at: nil} = subscriber(repo, "ada@example.com")
      assert subscriber(repo, "b@x.io") == nil
    end
  end

  describe "the feeds and the sitemap" do
    setup do
      {:ok, _} = Categories.create(%{"names" => %{"en" => "New"}})
      entry!("Shiny", %{published_at: minutes(-3), categories: ["new"]})
      entry!("Mended", %{published_at: minutes(-2)})
      entry!("For pro", %{published_at: minutes(-1), segments: ["plan:pro"]})
      entry!("A draft")
      :ok
    end

    test "the sitemap lists the page and the entries for everyone", %{conn: conn} do
      conn = get(conn, "/changelog/sitemap.xml")
      assert response_content_type(conn, :xml) =~ "application/xml"
      xml = response(conn, 200)

      locs = Regex.scan(~r{<loc>(.*?)</loc>}, xml, capture: :all_but_first) |> List.flatten()

      assert locs == [
               "http://www.example.com/changelog",
               "http://www.example.com/changelog/mended",
               "http://www.example.com/changelog/shiny"
             ]

      assert xml =~ "<lastmod>#{Date.to_iso8601(Date.utc_today())}</lastmod>"
    end

    test "the feeds of a category", %{conn: conn} do
      xml = conn |> get("/changelog/feed.xml?category=new") |> response(200)
      assert xml =~ "<title>Shiny</title>"
      refute xml =~ "Mended"
      refute xml =~ "For pro"

      xml = build_conn() |> get("/changelog/feed.xml") |> response(200)
      assert xml =~ "Mended"
      refute xml =~ "For pro"
      refute xml =~ "A draft"

      feed =
        build_conn()
        |> get("/changelog/feed.json?category=new")
        |> response(200)
        |> JSON.decode!()

      assert [%{"title" => "Shiny", "tags" => ["new"], "language" => "en"}] = feed["items"]
      assert feed["feed_url"] == "http://www.example.com/changelog/feed.json"
    end
  end
end
