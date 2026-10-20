defmodule Tayori.APITest do
  use TayoriTest.ConnCase

  defp as_reader(conn, reader), do: with_session(conn, %{"reader" => reader})

  defp json!(conn), do: JSON.decode!(conn.resp_body)

  # Tayori with some features, on the test's repo.
  defp features(%{repo: repo}, features) do
    Tayori.Config.put(
      Tayori.Config.new(
        repo: repo,
        pubsub: TayoriTest.PubSub,
        locales: ["en", "pt-PT"],
        secret_key_base: String.duplicate("tayori-test-secret-", 4),
        features: features
      )
    )
  end

  # A POST of the app's session, with its CSRF token.
  defp post_json(conn, path, body) do
    conn = get(conn, "/api/news/unread")
    token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> recycle()
    |> put_req_header("x-csrf-token", token)
    |> put_req_header("content-type", "application/json")
    |> post(path, JSON.encode!(body))
  end

  test "GET / gives the news of the reader, with the words around it", %{conn: conn} do
    entry!("Everyone", %{published_at: minutes(-2), categories: ["New"]})
    entry!("Pro", %{published_at: minutes(-1), segments: ["plan:pro"]})

    body = conn |> get("/api/news") |> json!()

    assert [
             %{
               "title" => "Everyone",
               "url" => "http://localhost/changelog/everyone",
               "categories" => [%{"key" => "New", "name" => "New", "color" => "gray"}]
             } = e
           ] = body["entries"]

    assert e["html"] =~ "About Everyone."
    assert body["unread"] == 0
    assert body["messages"]["title"] == "What's new"

    body =
      build_conn()
      |> as_reader(%{"id" => "u1", "segments" => ["plan:pro"]})
      |> get("/api/news")
      |> json!()

    assert Enum.map(body["entries"], & &1["title"]) == ["Pro", "Everyone"]
    assert body["unread"] == 2
  end

  test "pages with before, and the language of the browser", %{conn: conn} do
    for n <- 1..3, do: entry!("E#{n}", %{published_at: minutes(-10 + n)})

    first = conn |> get("/api/news?limit=2") |> json!()
    assert first["more"]
    last = List.last(first["entries"])["id"]

    rest = build_conn() |> get("/api/news?limit=2&before=#{last}") |> json!()
    assert Enum.map(rest["entries"], & &1["title"]) == ["E1"]
    refute rest["more"]

    body =
      build_conn()
      |> put_req_header("accept-language", "pt-BR,pt;q=0.9")
      |> get("/api/news")
      |> json!()

    assert body["messages"]["title"] == "Novidades"
  end

  test "unread, seen, and one entry", %{conn: conn} do
    entry!("Hello", %{published_at: minutes(-1)})
    conn = as_reader(conn, %{"id" => "u1"})

    assert conn |> get("/api/news/unread") |> json!() |> Map.fetch!("unread") == 1

    # The app's protect_from_forgery: the token of the session, as the
    # element sends it from the page's meta tag.
    conn = get(conn, "/api/news/unread")
    token = Plug.CSRFProtection.get_csrf_token()

    seen =
      conn
      |> recycle()
      |> put_req_header("x-csrf-token", token)
      |> post("/api/news/seen")

    assert json!(seen) == %{"unread" => 0}
    assert Tayori.unread_count(%Reader{id: "u1"}) == 0

    assert %{"entry" => %{"slug" => "hello"}} =
             conn |> recycle() |> get("/api/news/hello") |> json!()

    assert conn |> recycle() |> get("/api/news/nope") |> Map.get(:status) == 404
  end

  test "entries carry their cover, categories and pin, filtered by category and search",
       %{conn: conn} do
    {:ok, _} =
      Tayori.Categories.create(%{
        "names" => %{"en" => "New", "pt-PT" => "Novo"},
        "color" => "green"
      })

    plain = entry!("Plain boards", %{published_at: minutes(-3)})
    covered = entry!("Covered exports", %{published_at: minutes(-2), categories: ["new"]})

    {:ok, _} =
      Entries.put_cover_map(covered, %{
        "url" => "/c.png",
        "alt" => "The export",
        "width" => 1600,
        "height" => 900
      })

    {:ok, _} = Entries.pin(plain)

    body = conn |> get("/api/news") |> json!()
    assert [first, second] = body["entries"]
    assert %{"title" => "Plain boards", "pinned" => true, "cover" => nil} = first

    assert %{
             "pinned" => false,
             "cover" => %{"url" => "/c.png", "alt" => "The export", "width" => 1600},
             "categories" => [%{"key" => "new", "name" => "New", "color" => "green"}]
           } = second

    refute Map.has_key?(second, "reactions")
    assert body["signedIn"] == false
    # The tayori_page of the same router, whole.
    assert body["page"] == "http://localhost/changelog"
    assert body["features"] == []

    titles = fn path ->
      build_conn() |> get(path) |> json!() |> Map.fetch!("entries") |> Enum.map(& &1["title"])
    end

    assert titles.("/api/news?category=new") == ["Covered exports"]
    assert titles.("/api/news?q=boards") == ["Plain boards"]
    assert titles.("/api/news?category=nope") == []

    # The pinned entry is on the first page whatever the limit, and not on
    # the next.
    page = build_conn() |> get("/api/news?limit=1") |> json!()
    assert Enum.map(page["entries"], & &1["title"]) == ["Plain boards", "Covered exports"]
    refute page["more"]

    assert %{"categories" => [%{"key" => "new", "name" => "Novo", "color" => "green"}]} =
             build_conn()
             |> as_reader(%{"id" => "u1", "locale" => "pt-PT"})
             |> get("/api/news/categories")
             |> json!()
  end

  test "reactions: a reader toggles one, a visitor cannot, only the app's emoji", ctx do
    entry = entry!("Hello", %{published_at: minutes(-1)})
    path = "/api/news/#{entry.id}/reactions"
    reader = fn -> as_reader(build_conn(), %{"id" => "u1"}) end

    assert reader.() |> post_json(path, %{emoji: "🎉"}) |> Map.get(:status) == 404

    features(ctx, [:reactions])

    assert %{"reactions" => %{"counts" => %{"🎉" => 1}, "mine" => ["🎉"]}} =
             reader.() |> post_json(path, %{emoji: "🎉"}) |> json!()

    body = reader.() |> get("/api/news") |> json!()
    assert [%{"reactions" => %{"counts" => %{"🎉" => 1}, "mine" => ["🎉"]}}] = body["entries"]
    assert body["features"] == ["reactions"]
    assert body["emoji"] == ["👍", "🎉", "❤️", "🚀", "👀"]

    assert %{"reactions" => %{"counts" => %{}, "mine" => []}} =
             reader.() |> post_json(path, %{emoji: "🎉"}) |> json!()

    unknown = reader.() |> post_json(path, %{emoji: "💩"})
    assert {unknown.status, json!(unknown)} == {422, %{"error" => "unknown_emoji"}}

    visitor = build_conn() |> post_json(path, %{emoji: "🎉"})
    assert {visitor.status, json!(visitor)} == {401, %{"error" => "unauthorized"}}

    assert reader.() |> post_json("/api/news/nope/reactions", %{emoji: "🎉"}) |> Map.get(:status) ==
             404
  end

  test "the announcement of the reader, and its dismissal", ctx do
    {:ok, entry} =
      Entries.create(%{
        announce: "toast",
        translations: [
          %{locale: "en", title: "Boards", summary: "Share them.", cta_url: "/boards"}
        ]
      })

    {:ok, entry} = Entries.publish(entry, minutes(-1))
    reader = fn -> as_reader(build_conn(), %{"id" => "u1"}) end

    assert reader.() |> get("/api/news/announcement") |> Map.get(:status) == 404

    features(ctx, [:announcements])

    assert %{
             "announcement" => %{
               "id" => id,
               "title" => "Boards",
               "announce" => "toast",
               "until" => nil,
               "cta" => %{"url" => "/boards", "label" => nil}
             }
           } = reader.() |> get("/api/news/announcement") |> json!()

    assert id == entry.id
    assert build_conn() |> get("/api/news/announcement") |> json!() |> Map.get("announcement")

    assert reader.() |> post_json("/api/news/announcement/#{id}/dismiss", %{}) |> json!() ==
             %{"dismissed" => true}

    assert %{"announcement" => nil} = reader.() |> get("/api/news/announcement") |> json!()

    # A visitor's dismissal is the page's: nothing is kept.
    assert build_conn() |> post_json("/api/news/announcement/#{id}/dismiss", %{}) |> json!() ==
             %{"dismissed" => true}

    assert build_conn() |> get("/api/news/announcement") |> json!() |> Map.get("announcement")
  end

  test "an entry read through the API is a view from the widget", ctx do
    features(ctx, [:analytics])
    entry = entry!("Hello", %{published_at: minutes(-1)})

    ctx.conn |> as_reader(%{"id" => "u1"}) |> get("/api/news/hello")
    build_conn() |> get("/api/news/hello")

    assert Tayori.Views.totals([entry.id]) == %{entry.id => %{views: 2, readers: 1}}
    assert [{_today, %{"widget" => 2}}] = Tayori.Views.by_day(entry.id, Date.utc_today())
  end
end
