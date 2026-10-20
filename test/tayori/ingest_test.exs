defmodule Tayori.IngestTest do
  use TayoriTest.DataCase

  import Plug.Conn
  import Phoenix.ConnTest

  alias Tayori.API.Machines
  alias Tayori.{Inbox, Ingest, Settings}

  @endpoint TayoriTest.Host.Endpoint
  @path "/machines/news/changes"

  defp post_changes(body, token) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> then(&if(token, do: put_req_header(&1, "authorization", "Bearer " <> token), else: &1))
    |> post(@path, if(is_binary(body), do: body, else: JSON.encode!(body)))
  end

  defp json!(conn), do: JSON.decode!(conn.resp_body)

  for_each_repo do
    test "the token: made, kept as a hash, checked, replaced and revoked" do
      refute Ingest.token?()
      refute Ingest.verify("tyi_anything")

      assert {:ok, "tyi_" <> _ = token} = Ingest.new_token()
      assert Ingest.token?()
      assert Ingest.verify(token)
      refute Ingest.verify(token <> "x")
      refute Ingest.verify(nil)

      # Only its hash is kept, and no secret.
      setting = Settings.get("ingest")
      refute Enum.any?(Map.values(setting), &(&1 == token))
      refute Settings.secret?("ingest")

      assert {:ok, other} = Ingest.new_token()
      refute other == token
      refute Ingest.verify(token)
      assert Ingest.verify(other)

      assert Ingest.revoke_token() == :ok
      refute Ingest.token?()
      refute Ingest.verify(other)
    end

    test "POST /changes adds the changes, once, and counts them" do
      {:ok, token} = Ingest.new_token()

      body = %{
        changes: [
          %{ref: "pr-1", title: "Exports in two clicks", kind: "added", url: "https://x.test/1"},
          %{ref: "pr-2", title: "Faster search", source: "ci", highlight: true},
          %{ref: "pr-3", title: "", url: "javascript:alert(1)"},
          "not a change"
        ]
      }

      conn = post_changes(body, token)
      assert conn.status == 201
      assert get_resp_header(conn, "access-control-allow-origin") == []

      assert json!(conn) == %{
               "added" => 2,
               "existing" => 0,
               "errors" => [
                 %{
                   "index" => 2,
                   "errors" => %{
                     "title" => ["can't be blank"],
                     "url" => ["must be an http(s) address"]
                   }
                 },
                 %{"index" => 3, "errors" => %{"change" => ["must be an object"]}}
               ]
             }

      assert [%{source: "api", ref: "pr-1", kind: "added"}] = Inbox.list(source: "api")
      assert [%{source: "ci", highlight: true}] = Inbox.list(source: "ci")

      # The same changes again: nothing new.
      conn = post_changes(%{changes: Enum.take(body.changes, 2)}, token)
      assert conn.status == 200
      assert json!(conn) == %{"added" => 0, "existing" => 2, "errors" => []}

      # One change, and one that is all wrong.
      conn = post_changes(%{change: %{ref: "pr-4", title: "Dark mode"}}, token)
      assert {conn.status, json!(conn)["added"]} == {201, 1}

      conn = post_changes(%{change: %{ref: "pr-5"}}, token)
      assert conn.status == 422

      assert json!(conn)["errors"] == [
               %{"index" => 0, "errors" => %{"title" => ["can't be blank"]}}
             ]
    end

    test "POST /changes: no token made, no token, a wrong one" do
      conn = post_changes(%{changes: []}, "tyi_guess")
      assert {conn.status, json!(conn)} == {404, %{"error" => "not_found"}}

      {:ok, _token} = Ingest.new_token()

      conn = post_changes(%{changes: []}, nil)
      assert {conn.status, json!(conn)} == {401, %{"error" => "unauthorized"}}
      assert [~s(Bearer realm="tayori")] = get_resp_header(conn, "www-authenticate")

      conn = post_changes(%{changes: [%{ref: "a", title: "A"}]}, "tyi_guess")
      assert conn.status == 401
      assert Inbox.list() == []
    end

    test "POST /changes: a bad body, too many changes, too large a body" do
      {:ok, token} = Ingest.new_token()

      assert post_changes("{nope", token).status == 400
      assert json!(post_changes(%{entries: []}, token)) == %{"error" => "no_changes"}

      many = for i <- 1..501, do: %{ref: "r#{i}", title: "T#{i}"}
      conn = post_changes(%{changes: many}, token)
      assert {conn.status, json!(conn)} == {413, %{"error" => "too_many_changes"}}

      large = %{changes: [%{ref: "big", title: "Big", body: String.duplicate("a", 1_000_001)}]}
      conn = post_changes(large, token)
      assert {conn.status, json!(conn)} == {413, %{"error" => "too_large"}}

      assert Inbox.list() == []
    end

    test "POST /changes with a body the endpoint parsed" do
      {:ok, token} = Ingest.new_token()

      conn =
        Plug.Test.conn(:post, "/changes", %{"changes" => [%{"ref" => "p", "title" => "Parsed"}]})
        |> put_req_header("authorization", "Bearer " <> token)
        |> Machines.call(:changes)

      assert {conn.status, json!(conn)["added"]} == {201, 1}
      assert [%{title: "Parsed", source: "api"}] = Inbox.list()
    end
  end

  test "the mount with the session needs the CSRF token for a POST" do
    {:ok, _ctx} = TayoriTest.DataCase.checkout(TayoriTest.SQLiteRepo)
    {:ok, token} = Ingest.new_token()

    assert_error_sent 403, fn ->
      build_conn()
      # Phoenix.ConnTest skips the protection; the app's browsers do not.
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/news/changes", JSON.encode!(%{changes: [%{ref: "a", title: "A"}]}))
    end

    assert Inbox.list() == []
  end
end
