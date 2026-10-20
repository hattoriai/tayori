defmodule Tayori.APITest do
  use TayoriTest.ConnCase

  defp as_reader(conn, reader), do: with_session(conn, %{"reader" => reader})

  defp json!(conn), do: JSON.decode!(conn.resp_body)

  test "GET / gives the news of the reader, with the words around it", %{conn: conn} do
    entry!("Everyone", %{published_at: minutes(-2), categories: ["New"]})
    entry!("Pro", %{published_at: minutes(-1), segments: ["plan:pro"]})

    body = conn |> get("/api/news") |> json!()

    assert [%{"title" => "Everyone", "url" => "/changelog/everyone", "categories" => ["New"]} = e] =
             body["entries"]

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
end
