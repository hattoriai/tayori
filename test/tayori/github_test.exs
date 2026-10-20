defmodule Tayori.GitHubTest do
  use TayoriTest.DataCase

  import Plug.Conn
  import Phoenix.ConnTest
  import ExUnit.CaptureLog

  alias Tayori.API.Machines
  alias Tayori.{Config, GitHub, Inbox, Settings}

  @endpoint TayoriTest.Host.Endpoint
  @path "/machines/news/hooks/github"
  @fixtures Path.expand("../support/fixtures/github", __DIR__)

  doctest Tayori.GitHub

  defp fixture(name), do: File.read!(Path.join(@fixtures, name <> ".json"))
  defp payload(name), do: name |> fixture() |> JSON.decode!()

  defp sign(body, secret),
    do: "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

  defp deliver(event, body, signature) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", event)
    |> then(&if(signature, do: put_req_header(&1, "x-hub-signature-256", signature), else: &1))
    |> post(@path, body)
  end

  defp json!(conn), do: JSON.decode!(conn.resp_body)

  describe "the events" do
    setup do: TayoriTest.DataCase.checkout(TayoriTest.SQLiteRepo)

    test "a merged pull request: its title, its Changelog section, its labels" do
      assert {:ok, [change]} = GitHub.handle("pull_request", payload("pull_request_merged"))

      assert change == %{
               ref: "atelier/app#1234",
               title: "Exports in two clicks",
               body: "Zip a whole project, with its files and notes, and get a link by email.",
               kind: "added",
               segments: ["plan:pro"],
               highlight: true,
               url: "https://github.com/atelier/app/pull/1234",
               author: "hanzo",
               occurred_at: "2026-10-20T08:59:40Z",
               meta: %{
                 "repository" => "atelier/app",
                 "number" => 1234,
                 "labels" => [
                   "changelog:added",
                   "changelog:highlight",
                   "changelog:segment:plan:pro",
                   "frontend"
                 ]
               }
             }
    end

    test "the labels: skip, internal, category, and the prefix of the config", %{config: config} do
      pr = payload("pull_request_merged")

      labelled = fn names ->
        put_in(pr, ["pull_request", "labels"], Enum.map(names, &%{"name" => &1}))
      end

      assert {:ok, []} =
               GitHub.handle("pull_request", labelled.(["changelog:skip", "changelog:added"]))

      assert {:ok, [%{audience: "internal", category: "api", kind: "fixed"} = change]} =
               GitHub.handle(
                 "pull_request",
                 labelled.(["Changelog: Internal", "changelog:category:api", "changelog:fixed"])
               )

      assert change.highlight == false

      # No label of the prefix: a change with no kind, unless only labelled ones count.
      assert {:ok, [plain]} = GitHub.handle("pull_request", labelled.(["frontend"]))
      refute Map.has_key?(plain, :kind)

      assert {:ok, []} =
               GitHub.handle("pull_request", labelled.(["frontend"]), only_labeled: true)

      put_config(config, inbox: [github: [label_prefix: "news/", only_labeled: true]])
      assert {:ok, []} = GitHub.handle("pull_request", labelled.(["changelog:added"]))
      assert {:ok, [%{kind: "added"}]} = GitHub.handle("pull_request", labelled.(["news/added"]))
    end

    test "a pull request closed unmerged, or merged into another branch, is nothing" do
      assert GitHub.handle("pull_request", payload("pull_request_closed")) == :ignore

      opened = put_in(payload("pull_request_merged"), ["action"], "opened")
      assert GitHub.handle("pull_request", opened) == :ignore

      other = put_in(payload("pull_request_merged"), ["pull_request", "base", "ref"], "release-1")
      assert GitHub.handle("pull_request", other) == {:ok, []}
    end

    test "the description: the Changelog or Release notes section, never the rest" do
      assert GitHub.changelog_section(nil) == nil
      assert GitHub.changelog_section("Internal notes about the refactor.") == nil
      assert GitHub.changelog_section("## Changelog\n\n<!-- Say it for users -->\n\n## QA") == nil

      body = """
      Context for the team.

      ### Release notes:

      Search finds words in **bodies** too.

      #### Example

      Search "invoice".

      ### Screenshots

      None.
      """

      assert GitHub.changelog_section(body) ==
               "Search finds words in **bodies** too.\n\n#### Example\n\nSearch \"invoice\"."

      assert GitHub.changelog_section("# Change log\nDark mode.") == "Dark mode."
    end

    test "a published release: its items, with their kinds, without GitHub's credits" do
      assert {:ok, [added, fixed]} = GitHub.handle("release", payload("release_published"))

      assert %{
               title: "Exports in two clicks: zip a project with its files",
               kind: "added",
               version: "v1.4.0",
               url: "https://github.com/atelier/app/releases/tag/v1.4.0",
               author: "sakura",
               occurred_at: "2026-10-20T09:31:12Z"
             } = added

      refute Map.has_key?(added, :body)
      assert "atelier/app@v1.4.0/" <> _hash = added.ref
      assert %{title: "Dates showed a day early in Auckland", kind: "fixed"} = fixed
      refute added.ref == fixed.ref
    end

    test "release notes with no section, with no item, or a prerelease" do
      release = payload("release_published")
      with_body = &put_in(release, ["release", "body"], &1)

      assert {:ok, [first, %{title: "Fewer clicks"}]} =
               GitHub.handle("release", with_body.("- Faster exports.\n- Fewer clicks."))

      assert first.title == "Faster exports"
      refute Map.has_key?(first, :body)
      refute Map.has_key?(first, :kind)

      assert {:ok, [%{ref: "atelier/app@v1.4.0", title: "1.4.0", body: "A quieter release."}]} =
               GitHub.handle("release", with_body.("A quieter release."))

      assert {:ok, []} = GitHub.handle("release", with_body.(nil))

      pre = put_in(release, ["release", "prerelease"], true)
      assert GitHub.handle("release", pre) == :ignore
      assert GitHub.handle("release", put_in(release, ["action"], "created")) == :ignore
    end

    test "ping and other events" do
      assert GitHub.handle("ping", payload("ping")) == {:ok, []}
      assert GitHub.handle("issues", %{"action" => "opened"}) == :ignore
    end
  end

  for_each_repo do
    test "the secret: made, kept encrypted, removed" do
      refute GitHub.secret?()
      assert {:ok, secret} = GitHub.new_secret()
      assert GitHub.secret?()
      assert Settings.secret("github") == secret

      config = Config.get()
      row = config.repo.get(Settings.Setting, "github", prefix: config.prefix)
      refute row.secret == secret
      refute row.secret =~ secret

      assert GitHub.verify("{}", sign("{}", secret)) == :ok
      assert GitHub.verify("{}", sign("{}", "another")) == {:error, :invalid}
      assert GitHub.verify("{}", nil) == {:error, :invalid}

      assert GitHub.remove_secret() == :ok
      refute GitHub.secret?()
      assert GitHub.verify("{}", sign("{}", secret)) == {:error, :no_secret}
    end

    test "no secret without a vault or a secret_key_base", %{config: config} do
      put_config(config, secret_key_base: nil)
      assert GitHub.new_secret() == {:error, :no_secrets}
      refute GitHub.secret?()
    end

    test "the webhook: a merged pull request, signed, added once" do
      {:ok, secret} = GitHub.new_secret()
      body = fixture("pull_request_merged")

      conn = deliver("pull_request", body, sign(body, secret))
      assert {conn.status, json!(conn)} == {200, %{"added" => 1, "existing" => 0, "errors" => []}}

      assert [%{source: "github", ref: "atelier/app#1234", kind: "added", highlight: true}] =
               Inbox.list()

      conn = deliver("pull_request", body, sign(body, secret))
      assert json!(conn) == %{"added" => 0, "existing" => 1, "errors" => []}
    end

    test "the webhook: a release, a ping, a closed pull request, another event" do
      {:ok, secret} = GitHub.new_secret()

      body = fixture("release_published")
      conn = deliver("release", body, sign(body, secret))
      assert {conn.status, json!(conn)["added"]} == {200, 2}

      body = fixture("ping")
      conn = deliver("ping", body, sign(body, secret))
      assert {conn.status, json!(conn)["added"]} == {200, 0}

      body = fixture("pull_request_closed")
      conn = deliver("pull_request", body, sign(body, secret))
      assert {conn.status, json!(conn)} == {202, %{"ignored" => "pull_request"}}

      body = ~s({"action": "opened", "issue": {"number": 1}})
      conn = deliver("issues", body, sign(body, secret))
      assert conn.status == 202

      assert length(Inbox.list()) == 2
    end

    test "the webhook: no secret, no signature, a wrong one" do
      body = fixture("pull_request_merged")

      conn = deliver("pull_request", body, sign(body, "guess"))
      assert {conn.status, json!(conn)} == {404, %{"error" => "not_found"}}

      {:ok, secret} = GitHub.new_secret()

      assert deliver("pull_request", body, nil).status == 401
      conn = deliver("pull_request", body, sign(body, "guess"))
      assert {conn.status, json!(conn)} == {401, %{"error" => "invalid_signature"}}

      # Signed, then changed.
      changed = String.replace(body, "Exports", "Imports")
      assert deliver("pull_request", changed, sign(body, secret)).status == 401

      assert Inbox.list() == []
    end

    test "the webhook behind Plug.Parsers: the raw body kept by read_body/2" do
      {:ok, secret} = GitHub.new_secret()
      body = fixture("pull_request_merged")

      parsers =
        Plug.Parsers.init(
          parsers: [:json],
          pass: ["*/*"],
          json_decoder: JSON,
          body_reader: {GitHub, :read_body, []}
        )

      request = fn signature ->
        Plug.Test.conn(:post, "/hooks/github", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "pull_request")
        |> put_req_header("x-hub-signature-256", signature)
      end

      conn = request.(sign(body, secret)) |> Plug.Parsers.call(parsers)
      assert conn.body_params["number"] == 1234
      conn = Machines.call(conn, :github)
      assert {conn.status, json!(conn)["added"]} == {200, 1}

      # Without the body reader, Tayori cannot check the signature, and says so.
      parsers = Plug.Parsers.init(parsers: [:json], pass: ["*/*"], json_decoder: JSON)

      log =
        capture_log(fn ->
          conn = request.(sign(body, secret)) |> Plug.Parsers.call(parsers)
          conn = Machines.call(conn, :github)
          assert {conn.status, json!(conn)} == {500, %{"error" => "no_raw_body"}}
        end)

      assert log =~ "body_reader: {Tayori.GitHub, :read_body, []}"

      # Another request is not copied.
      conn =
        Plug.Test.conn(:post, "/other", ~s({"a": 1}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(
          Plug.Parsers.init(
            parsers: [:json],
            json_decoder: JSON,
            body_reader: {GitHub, :read_body, []}
          )
        )

      refute Map.has_key?(conn.private, :tayori_raw_body)
    end

    test "a form-encoded delivery" do
      {:ok, secret} = GitHub.new_secret()
      body = URI.encode_query(%{"payload" => fixture("ping")})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("x-github-event", "ping")
        |> put_req_header("x-hub-signature-256", sign(body, secret))
        |> post(@path, body)

      assert conn.status == 200
    end
  end
end
