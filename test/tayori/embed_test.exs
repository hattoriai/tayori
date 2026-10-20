defmodule Tayori.EmbedTest do
  use TayoriTest.ConnCase

  alias Tayori.{Config, Embed}

  @secret String.duplicate("tayori-test-secret-", 4)
  @site "https://www.atelier.test"

  defp config(repo, opts) do
    Config.new(
      Keyword.merge(
        [
          repo: repo,
          pubsub: TayoriTest.PubSub,
          locales: ["en", "pt-PT"],
          secret_key_base: @secret
        ],
        opts
      )
    )
  end

  defp embed(%{repo: repo}, opts \\ []) do
    Config.put(
      config(
        repo,
        Keyword.merge(
          [features: [:embed, :reactions], embed: [origins: [@site, "http://localhost:4000"]]],
          opts
        )
      )
    )
  end

  defp json!(conn), do: JSON.decode!(conn.resp_body)

  defp from_site(conn, origin \\ @site), do: put_req_header(conn, "origin", origin)

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp reader, do: %Reader{id: "u1", segments: ["plan:pro"], locale: "pt-PT"}

  describe "the config" do
    test "the feature needs the origins and the secret", %{repo: repo} do
      assert_raise ArgumentError, ~r/needs the :embed option/, fn ->
        config(repo, features: [:embed])
      end

      assert_raise ArgumentError, ~r/needs the :secret_key_base option/, fn ->
        config(repo, features: [:embed], embed: [origins: [@site]], secret_key_base: nil)
      end

      config = config(repo, features: [:embed], embed: [origins: [@site]])
      assert config.embed == %{origins: [@site], max_age: 86_400}
    end

    test "an origin is a scheme and a host, with a port when not the default", %{repo: repo} do
      config =
        config(repo,
          features: [:embed],
          embed: [
            origins: ["HTTPS://WWW.Atelier.test:443", "http://localhost:4000", "http://[::1]:80"],
            max_age: 600
          ]
        )

      assert config.embed == %{
               origins: [@site, "http://localhost:4000", "http://[::1]"],
               max_age: 600
             }

      for bad <- [
            "*",
            "https://*.atelier.test",
            "https://www.atelier.test/",
            "https://www.atelier.test/news",
            "www.atelier.test",
            "ftp://atelier.test",
            "https://user@atelier.test",
            "https://atelier.test?x=1"
          ] do
        assert_raise ArgumentError, ~r/each origin of :embed/, fn ->
          config(repo, features: [:embed], embed: [origins: [bad]])
        end
      end

      assert_raise ArgumentError, ~r/:origins of :embed/, fn ->
        config(repo, features: [:embed], embed: [origins: []])
      end

      assert_raise ArgumentError, ~r/:max_age of :embed/, fn ->
        config(repo, features: [:embed], embed: [origins: [@site], max_age: 0])
      end

      assert_raise ArgumentError, ~r/:embed takes :origins and :max_age/, fn ->
        config(repo, features: [:embed], embed: [origins: [@site], credentials: true])
      end
    end
  end

  describe "the reader token" do
    test "carries the reader, signed", ctx do
      embed(ctx)
      since = ~U[2026-01-01 00:00:00.000000Z]
      token = Embed.token(%{reader() | since: since})

      assert Embed.verify(token) == {:ok, %{reader() | since: since}}
      assert Embed.verify(token <> "x") == {:error, :invalid}
      assert Embed.verify("not a token") == {:error, :invalid}

      # Signed with another secret, or another salt: not Tayori's.
      assert Embed.verify(
               Phoenix.Token.sign(String.duplicate("x", 64), "tayori embed reader", %{})
             ) ==
               {:error, :invalid}

      assert Embed.verify(Phoenix.Token.sign(@secret, "another salt", %{"id" => "u2"})) ==
               {:error, :invalid}
    end

    test "expires after :max_age", ctx do
      embed(ctx, embed: [origins: [@site], max_age: 60])

      old =
        Phoenix.Token.sign(
          @secret,
          "tayori embed reader",
          %{"id" => "u1", "segments" => [], "locale" => nil, "since" => nil},
          signed_at: System.system_time(:second) - 120
        )

      assert Embed.verify(old) == {:error, :expired}
    end

    test "is for readers, with the feature on", ctx do
      embed(ctx)

      assert_raise ArgumentError, ~r/a visitor has no reader token/, fn ->
        Embed.token(Reader.visitor())
      end

      token = Embed.token(reader())
      Config.put(config(ctx.repo, []))

      assert_raise ArgumentError, ~r/the :embed feature, which is off/, fn ->
        Embed.token(reader())
      end

      assert Embed.verify(token) == {:error, :invalid}
    end
  end

  describe "CORS" do
    test "a preflight of a site of the feature, and of no other", ctx do
      embed(ctx)

      conn =
        build_conn()
        |> from_site()
        |> put_req_header("access-control-request-method", "POST")
        |> put_req_header("access-control-request-headers", "authorization, content-type")
        |> options("/embed/news/0193/reactions")

      assert conn.status == 204
      assert get_resp_header(conn, "access-control-allow-origin") == [@site]
      assert get_resp_header(conn, "access-control-allow-methods") == ["GET, POST"]

      assert get_resp_header(conn, "access-control-allow-headers") == [
               "authorization, content-type"
             ]

      assert get_resp_header(conn, "access-control-allow-credentials") == []
      assert get_resp_header(conn, "vary") == ["origin"]

      assert build_conn() |> from_site() |> options("/embed/news") |> Map.get(:status) == 204

      for origin <- ["https://evil.test", "null", "https://www.atelier.test.evil.test"] do
        conn = build_conn() |> from_site(origin) |> options("/embed/news")
        assert conn.status == 403
        assert get_resp_header(conn, "access-control-allow-origin") == []
      end

      Config.put(config(ctx.repo, []))
      assert build_conn() |> from_site() |> options("/embed/news") |> Map.get(:status) == 404
    end

    test "the answers carry the site's origin back, and never credentials", ctx do
      embed(ctx)
      entry!("Hello", %{published_at: minutes(-1)})

      conn = build_conn() |> from_site("https://WWW.atelier.test") |> get("/embed/news")
      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") == [@site]
      assert get_resp_header(conn, "access-control-allow-credentials") == []
      assert get_resp_header(conn, "vary") == ["origin"]

      conn = build_conn() |> from_site("https://evil.test") |> get("/embed/news")
      assert get_resp_header(conn, "access-control-allow-origin") == []
      assert get_resp_header(conn, "vary") == ["origin"]

      # The app's own mount answers the sites too, and its pages need nothing.
      conn = build_conn() |> from_site() |> get("/api/news/unread")
      assert get_resp_header(conn, "access-control-allow-origin") == [@site]

      Config.put(config(ctx.repo, []))
      conn = build_conn() |> from_site() |> get("/embed/news")
      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") == []
      assert get_resp_header(conn, "vary") == []
    end
  end

  describe "the API with a reader token" do
    test "reads the reader from the token, not from the request", ctx do
      embed(ctx)
      entry!("For everyone", %{published_at: minutes(-2)})
      entry!("For pro", %{published_at: minutes(-1), segments: ["plan:pro"]})

      body = build_conn() |> from_site() |> bearer(Embed.token(reader())) |> get("/embed/news")
      body = json!(body)

      assert Enum.map(body["entries"], & &1["title"]) == ["For pro", "For everyone"]
      assert body["unread"] == 2
      assert body["signedIn"]
      assert body["messages"]["title"] == "Novidades"
      assert hd(body["entries"])["url"] == "https://app.test/changelog/for-pro"

      # Without a token, a visitor; an id the page sends means nothing.
      body = build_conn() |> from_site() |> get("/embed/news?reader=u1&id=u1") |> json!()
      assert Enum.map(body["entries"], & &1["title"]) == ["For everyone"]
      refute body["signedIn"]

      # A token that is not Tayori's (the app's own, for its own API) goes
      # to the resolver, and the reader of the session wins nothing here:
      # a page on another origin has no session.
      body =
        build_conn()
        |> from_site()
        |> bearer("the-app's-own-token")
        |> get("/embed/news")
        |> json!()

      refute body["signedIn"]
    end

    test "a reader on another origin marks the news seen and reacts, with no cookie", ctx do
      embed(ctx)
      entry = entry!("Hello", %{published_at: minutes(-1)})
      token = Embed.token(reader())

      conn = build_conn() |> from_site() |> bearer(token) |> post("/embed/news/seen")
      assert json!(conn) == %{"unread" => 0}
      assert Tayori.unread_count(reader()) == 0

      conn =
        build_conn()
        |> from_site()
        |> bearer(token)
        |> put_req_header("content-type", "application/json")
        |> post("/embed/news/#{entry.id}/reactions", JSON.encode!(%{emoji: "🚀"}))

      assert json!(conn) == %{"reactions" => %{"counts" => %{"🚀" => 1}, "mine" => ["🚀"]}}
      assert get_resp_header(conn, "access-control-allow-origin") == [@site]

      conn =
        build_conn()
        |> from_site()
        |> put_req_header("content-type", "application/json")
        |> post("/embed/news/#{entry.id}/reactions", JSON.encode!(%{emoji: "🚀"}))

      assert conn.status == 401
    end

    test "an expired token is a 401, which the page can read", ctx do
      embed(ctx, embed: [origins: [@site], max_age: 60])

      old =
        Phoenix.Token.sign(
          @secret,
          "tayori embed reader",
          %{"id" => "u1", "segments" => [], "locale" => nil, "since" => nil},
          signed_at: System.system_time(:second) - 120
        )

      conn = build_conn() |> from_site() |> bearer(old) |> get("/embed/news/unread")
      assert conn.status == 401
      assert json!(conn) == %{"error" => "token_expired"}
      assert get_resp_header(conn, "www-authenticate") == [~s(Bearer error="invalid_token")]
      assert get_resp_header(conn, "access-control-allow-origin") == [@site]
    end

    test "the token means nothing with the feature off", ctx do
      embed(ctx)
      token = Embed.token(reader())
      Config.put(config(ctx.repo, []))

      body = build_conn() |> bearer(token) |> get("/embed/news/unread") |> json!()
      refute body["signedIn"]
    end
  end

  describe "the script and the style sheets" do
    test "are served to the sites, with the feature on", ctx do
      embed(ctx)

      conn = build_conn() |> from_site() |> get("/embed/news/tayori.js")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
      assert get_resp_header(conn, "access-control-allow-origin") == [@site]
      assert get_resp_header(conn, "vary") == ["origin, accept-encoding"]
      assert [etag] = get_resp_header(conn, "etag")

      {"text/javascript", _hash, body, _gzipped} = Embed.asset("tayori.js")
      assert conn.resp_body == body

      conn = build_conn() |> put_req_header("if-none-match", etag) |> get("/embed/news/tayori.js")
      assert conn.status == 304

      conn =
        build_conn()
        |> put_req_header("accept-encoding", "gzip, br")
        |> get("/embed/news/tayori-sumi.css")

      assert get_resp_header(conn, "content-encoding") == ["gzip"]
      assert get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
      {"text/css", _hash, css, _gzipped} = Embed.asset("tayori-sumi.css")
      assert :zlib.gunzip(conn.resp_body) == css

      assert build_conn() |> get("/embed/news/tayori.css") |> Map.get(:status) == 200

      Config.put(config(ctx.repo, []))
      assert build_conn() |> get("/embed/news/tayori.js") |> Map.get(:status) == 404
    end
  end
end
