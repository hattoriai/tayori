defmodule Tayori.ModulesTest do
  use TayoriTest.ConnCase

  import Sake.Test, only: [list_tools: 1]

  alias Tayori.Config

  @admin %{"role" => "admin", "id" => 7, "name" => "Hanzo"}

  # The campaigns alone: no changelog.
  defp campaigns_only(%{config: config}) do
    opts = Keyword.put(TayoriTest.DataCase.campaigns_config(), :modules, [:campaigns])
    {:ok, config: put_config(config, opts)}
  end

  describe "the default modules" do
    test "are the changelog's: the admin, its nav and its pages, as before", %{conn: conn} do
      config = Config.get()
      assert config.modules == [:changelog]

      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news")
      assert html =~ "New entry"
      assert html =~ ~s(href="/admin/news/inbox")
      assert html =~ ~s(href="/admin/news/categories")
      refute html =~ "Campaigns"
      refute html =~ "Audience"

      assert conn |> get("/changelog") |> html_response(200)
      assert conn |> get("/api/news") |> json_response(200)
    end
  end

  describe "with the campaigns too" do
    setup :campaigns_on

    test "the nav adds Campaigns and Audience, beside the changelog's", %{conn: conn} do
      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news")
      assert html =~ "New entry"
      assert html =~ ~s(href="/admin/news/inbox")
      assert html =~ ~s(href="/admin/news/campaigns")
      assert html =~ ~s(href="/admin/news/audience")
    end
  end

  defp campaigns_on(%{config: config}),
    do: {:ok, config: put_config(config, TayoriTest.DataCase.campaigns_config())}

  describe "without the changelog" do
    setup :campaigns_only

    test "the admin's first page is the campaigns", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/news/campaigns"}}} =
               conn |> as_admin() |> live("/admin/news")

      # Who may not see the admin is still stopped first.
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/admin/news")
    end

    test "the entries, the inbox and the categories are not there", %{conn: conn} do
      entry = entry!("Hidden")

      for path <- ["/new", "/inbox", "/categories", "/#{entry.id}"] do
        assert_raise Tayori.Admin.NotFound, fn ->
          conn |> as_admin() |> live("/admin/news" <> path)
        end
      end
    end

    test "the nav has no Entries, Inbox, Categories or New entry", %{conn: conn} do
      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news/settings")
      [html] = Regex.run(~r{<header class="ta-bar">.*?</header>}s, html)
      refute html =~ "New entry"
      refute html =~ ~s(href="/admin/news/inbox")
      refute html =~ ~s(href="/admin/news/categories")
      refute html =~ ~r{href="/admin/news"[^/]}
      assert html =~ ~s(href="/admin/news/campaigns")
      assert html =~ ~s(href="/admin/news/audience")
      assert html =~ ~s(href="/admin/news/settings")
    end

    test "the JSON API answers 404, for readers and for machines", %{conn: conn} do
      entry!("Out", %{published_at: minutes(-1)})

      for path <- ["/api/news", "/api/news/unread", "/api/news/out", "/api/news/tayori.js"] do
        assert %{"error" => "not_found"} = conn |> get(path) |> json_response(404)
      end

      assert conn |> post("/api/news/seen") |> json_response(404)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer anything")
        |> post("/machines/news/changes", JSON.encode!(%{changes: []}))

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end

    test "the public page and its feeds answer 404", %{conn: conn} do
      entry!("Out", %{published_at: minutes(-1)})

      for path <- ["/changelog", "/changelog/out", "/changelog/feed.xml", "/news"] do
        assert conn |> get(path) |> response(404) == "Not Found"
      end
    end

    test "Tayori.Live assigns nil, and the components render nothing", %{conn: conn} do
      entry!("Out", %{published_at: minutes(-1)})

      {:ok, view, html} =
        conn |> with_session(%{"reader" => %{"id" => "u1"}}) |> live("/")

      refute html =~ "tayori-button"
      refute html =~ "tayori-panel"

      # It hears nothing of the news.
      entry!("Later", %{published_at: minutes(-1)})
      refute render(view) =~ "tayori"
    end

    test "the scheduler and the boot of the jobs do none of the changelog's work", %{
      config: config,
      repo: repo
    } do
      entry!("Due", %{published_at: minutes(-1)})
      assert Tayori.Scheduler.announce_due(config) == []
      assert Tayori.Scheduler.run_due(config) == :ok
      assert Tayori.Entries.list() |> hd() |> Map.get(:announced_at) == nil

      config = put_config(config, oban: TayoriTest.SQLiteOban, digest: [every: :weekly])
      assert :ok = Tayori.Jobs.boot(config)

      assert Oban.Testing.all_enqueued(
               repo: repo,
               engine: Oban.Engines.Lite,
               worker: Tayori.Worker
             ) ==
               []
    end

    test "the changelog's MCP tools are not listed", %{config: config} do
      put_config(config, mcp: [resolver: TayoriTest.Resolver])

      assert {:ok, []} =
               list_tools(
                 Sake.Test.connect(Tayori.MCP,
                   scope: @admin,
                   scopes: ["tayori:read", "tayori:write"]
                 )
               )
    end
  end

  test "MCP: a tool belongs to the campaigns by its module" do
    assert Tayori.MCP.Access.module_of(%{module: Tayori.MCP.Tools.ListEntries}) == :changelog

    assert Tayori.MCP.Access.module_of(%{module: Tayori.MCP.Tools.Campaigns.ListCampaigns}) ==
             :campaigns
  end
end
