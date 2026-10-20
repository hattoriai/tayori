defmodule Tayori.APIUITest do
  # The panel as HTML, for <tayori-news>: the components of the LiveView,
  # rendered by Tayori.API.
  use TayoriTest.ConnCase

  defp as_reader(conn, reader), do: with_session(conn, %{"reader" => reader})

  defp json!(conn), do: JSON.decode!(conn.resp_body)

  defp post_ui(conn, path) do
    conn = get(conn, "/api/news/unread")
    token = Plug.CSRFProtection.get_csrf_token()
    conn |> recycle() |> put_req_header("x-csrf-token", token) |> post(path)
  end

  # The classes and words of a piece of HTML, without the ids and the
  # attributes LiveView adds, and without the links to the public page
  # (the test's LiveView has no :page).
  defp shape(html) do
    nodes = html |> String.replace(~r{<a [^>]*>.*?</a>}s, "") |> LazyHTML.from_fragment()

    classes =
      nodes
      |> LazyHTML.query("[class]")
      |> LazyHTML.attribute("class")

    # LiveViewTest's render keeps less whitespace between the tags.
    {classes, nodes |> LazyHTML.text() |> String.replace(~r/\s+/u, "")}
  end

  test "the button, with the reader's count of unread entries", %{conn: conn} do
    entry!("Exports", %{published_at: minutes(-1)})

    body = conn |> get("/api/news/ui/button") |> json!()
    assert body["unread"] == 0
    assert body["html"] =~ ~s(class="tayori-button )
    refute body["html"] =~ "tayori-badge"

    body =
      build_conn()
      |> as_reader(%{"id" => "u1"})
      |> get("/api/news/ui/button?label=1")
      |> json!()

    assert body["unread"] == 1
    assert body["html"] =~ ~s(phx-click="tayori:open")
    assert body["html"] =~ "tayori-badge"
    assert body["html"] =~ "tayori-button-label"
  end

  test "opening marks the news seen, and keeps what was new marked", %{conn: conn} do
    entry!("Exports", %{published_at: minutes(-1)})
    conn = as_reader(conn, %{"id" => "u1"})

    body = conn |> post_ui("/api/news/ui/panel") |> json!()
    assert body["html"] =~ ~s(id="tayori-panel")
    assert body["html"] =~ "Exports"
    assert body["html"] =~ "tayori-new"
    assert is_binary(body["since"])

    assert Tayori.unread_count(%Tayori.Reader{id: "u1"}) == 0

    body =
      build_conn()
      |> as_reader(%{"id" => "u1"})
      |> get("/api/news/ui/panel", since: body["since"])
      |> json!()

    assert body["html"] =~ "tayori-new"
  end

  test "the panel of the API is the LiveView's panel", %{conn: conn} do
    entry!("Exports", %{published_at: minutes(-2), categories: ["New"]})
    entry!("Boards", %{published_at: minutes(-1)})

    {:ok, view, _html} = live(conn, "/")
    view |> element(".tayori-button") |> render_click()
    live = view |> element("#tayori-panel") |> render()

    api = build_conn() |> get("/api/news/ui/panel") |> json!()

    assert shape(api["html"]) == shape(live)
  end

  test "the views of the panel: a category, more pages, an entry", %{conn: conn} do
    exports = entry!("Exports", %{published_at: minutes(-3), categories: ["New"]})
    entry!("Boards", %{published_at: minutes(-2)})
    hidden = entry!("For Pro", %{published_at: minutes(-1), segments: ["plan:pro"]})

    html = conn |> get("/api/news/ui/panel", category: "New") |> json!() |> Map.get("html")
    assert html =~ "Exports"
    refute html =~ "Boards"

    body = build_conn() |> get("/api/news/ui/panel", entry: exports.id) |> json!()
    assert body["entry"] == exports.id
    assert body["html"] =~ ~s(id="tayori-panel-entry")
    assert body["html"] =~ "About Exports."
    assert body["html"] =~ ~s(phx-click="tayori:back")

    # Only an entry the reader has in front of them.
    assert build_conn() |> get("/api/news/ui/panel", entry: hidden.id) |> json_response(404)
    assert build_conn() |> get("/api/news/ui/panel", entry: "nope") |> json_response(404)
  end

  test "the announcement, as a popup, a toast or a banner", %{conn: conn, config: config} do
    assert conn |> get("/api/news/ui/announcement") |> json_response(404)

    put_config(config, features: [:announcements])

    assert build_conn() |> get("/api/news/ui/announcement") |> json!() == %{
             "html" => nil,
             "id" => nil,
             "kind" => nil
           }

    entry = entry!("Timeline", %{published_at: minutes(-1), announce: "popup"})
    body = build_conn() |> get("/api/news/ui/announcement") |> json!()
    assert body["id"] == entry.id
    assert body["kind"] == "popup"
    assert body["html"] =~ "tayori-announcement-popup"
    assert body["html"] =~ ~s(phx-click="tayori:dismiss")

    # Reading it answers it, for the reader.
    reader = build_conn() |> as_reader(%{"id" => "u1"})
    assert reader |> get("/api/news/ui/panel", entry: entry.id) |> json!() |> Map.get("entry")

    assert build_conn()
           |> as_reader(%{"id" => "u1"})
           |> get("/api/news/ui/announcement")
           |> json!()
           |> Map.get("id") == nil
  end
end
