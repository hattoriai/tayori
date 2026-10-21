defmodule Tayori.WebhooksTest do
  use TayoriTest.DataCase

  alias Tayori.Webhooks

  # Each request a place gets, sent to the test, answered with a status.
  defp stub(status \\ 200) do
    test = self()

    Req.Test.stub(Tayori.Webhooks, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn, body})
      Plug.Conn.send_resp(conn, status, "")
    end)
  end

  defp id_of(name), do: Enum.find(Webhooks.list(), &(&1["name"] == name))["id"]

  for_each_repo do
    setup %{config: config} do
      %{config: put_config(config, features: [:webhooks], page_url: "https://atelier.test/news")}
    end

    test "a place is added with an https address, a kind and a name" do
      assert {:error, :not_https} = Webhooks.add("slack", "Team", "http://hooks.test/x")
      assert {:error, :not_https} = Webhooks.add("slack", "Team", "https://")
      assert {:error, :not_https} = Webhooks.add("slack", "Team", "javascript:alert(1)")
      assert {:error, :unknown_kind} = Webhooks.add("teams", "Team", "https://hooks.test/x")
      assert {:error, :no_name} = Webhooks.add("slack", "  ", "https://hooks.test/x")
      assert Webhooks.list() == []

      assert {:ok, nil} =
               Webhooks.add("slack", " #product ", "https://hooks.slack.test/T1/B2/s3cr3t")

      assert {:ok, nil} =
               Webhooks.add("discord", "Discord", "https://discord.test/api/webhooks/1/x")

      assert {:ok, given} = Webhooks.add("webhook", "Ours", "https://ours.test/hook", "shh")
      assert given == "shh"
      assert {:ok, made} = Webhooks.add("webhook", "Made", "https://ours.test/other")
      assert byte_size(made) >= 32

      assert [
               %{"kind" => "slack", "name" => "#product", "host" => "hooks.slack.test"},
               %{"kind" => "discord", "name" => "Discord", "host" => "discord.test"},
               %{"kind" => "webhook", "name" => "Ours", "host" => "ours.test"},
               %{"kind" => "webhook", "name" => "Made"}
             ] = Webhooks.list()
    end

    test "the list shows no secret and no secret part of the addresses" do
      {:ok, secret} = Webhooks.add("webhook", "Ours", "https://ours.test/hook/s3cr3t-path", "shh")
      [hook] = Webhooks.list()

      assert Map.keys(hook) |> Enum.sort() == ["host", "id", "kind", "name"]
      refute inspect(hook) =~ secret
      refute inspect(hook) =~ "s3cr3t-path"

      # Kept encrypted in the database.
      refute inspect(Tayori.Settings.get("webhooks")) =~ "s3cr3t"
      assert Tayori.Settings.get("webhooks") == %{"count" => 1}
    end

    test "without a vault or a secret_key_base, no place can be kept", %{config: config} do
      put_config(config, secret_key_base: nil)
      assert {:error, :no_secrets} = Webhooks.add("slack", "Team", "https://hooks.test/x")
    end

    test "a place is removed" do
      {:ok, _} = Webhooks.add("slack", "One", "https://hooks.test/1")
      {:ok, _} = Webhooks.add("slack", "Two", "https://hooks.test/2")

      assert :ok = Webhooks.remove(id_of("One"))
      assert [%{"name" => "Two"}] = Webhooks.list()
      assert :ok = Webhooks.remove("unknown")
      assert [%{"name" => "Two"}] = Webhooks.list()
    end

    test "a webhook gets the entry as JSON, signed with its secret", %{config: config} do
      stub()
      {:ok, secret} = Webhooks.add("webhook", "Ours", "https://ours.test/hook")

      entry =
        entry!("Exports", %{
          published_at: minutes(-1),
          categories: ["new"],
          translations: [
            %{
              locale: "en",
              title: "Exports",
              summary: "Fast",
              body: Kotoba.Content.from_markdown("In **two** clicks.")
            },
            %{locale: "pt-PT", title: "Exportações"}
          ]
        })

      assert :ok = Webhooks.deliver(config, entry.id, id_of("Ours"))
      assert_received {:request, conn, body}

      assert conn.method == "POST"
      assert conn.host == "ours.test"
      assert conn.request_path == "/hook"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]

      signature = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
      assert Plug.Conn.get_req_header(conn, "x-tayori-signature") == ["sha256=" <> signature]

      assert %{
               "event" => "entry.published",
               "entry" => %{
                 "id" => id,
                 "slug" => "exports",
                 "categories" => ["new"],
                 "segments" => [],
                 "publishedAt" => published_at,
                 "url" => "https://atelier.test/news/exports",
                 "translations" => %{
                   "en" => %{
                     "title" => "Exports",
                     "summary" => "Fast",
                     "html" => "<p>In <strong>two</strong> clicks.</p>",
                     "text" => "In two clicks."
                   },
                   "pt-PT" => %{"title" => "Exportações", "summary" => nil}
                 }
               }
             } = JSON.decode!(body)

      assert id == entry.id
      assert {:ok, _, _} = DateTime.from_iso8601(published_at)
    end

    test "Slack and Discord get a message of the title, summary and link", %{config: config} do
      stub()
      {:ok, nil} = Webhooks.add("slack", "Slack", "https://hooks.slack.test/x")
      {:ok, nil} = Webhooks.add("discord", "Discord", "https://discord.test/x")

      entry =
        entry!("Exports", %{
          published_at: minutes(-1),
          translations: [%{locale: "en", title: "Exports", summary: "In two clicks"}]
        })

      :ok = Webhooks.deliver(config, entry.id, id_of("Slack"))
      assert_received {:request, conn, body}
      assert Plug.Conn.get_req_header(conn, "x-tayori-signature") == []

      assert JSON.decode!(body) == %{
               "text" => "Exports\nIn two clicks\nhttps://atelier.test/news/exports"
             }

      no_summary = entry!("Boards", %{published_at: minutes(-1)})
      put_config(config, page_url: nil)
      :ok = Webhooks.deliver(Tayori.Config.get(), no_summary.id, id_of("Discord"))
      assert_received {:request, _conn, body}
      assert JSON.decode!(body) == %{"content" => "Boards"}
    end

    test "the places for an entry: Slack and Discord only get the entries for everyone", %{
      config: config
    } do
      {:ok, _} = Webhooks.add("webhook", "Ours", "https://ours.test/hook")
      {:ok, _} = Webhooks.add("slack", "Slack", "https://hooks.slack.test/x")
      {:ok, _} = Webhooks.add("discord", "Discord", "https://discord.test/x")

      public = entry!("Public", %{published_at: minutes(-1)})
      pro = entry!("Pro", %{published_at: minutes(-1), segments: ["plan:pro"]})

      assert Webhooks.targets(config, public.id) ==
               Enum.map(~w(Ours Slack Discord), &id_of/1)

      assert Webhooks.targets(config, pro.id) == [id_of("Ours")]
      assert Webhooks.targets(config, Ecto.UUID.generate()) == []

      off = put_config(config, features: [])
      assert Webhooks.targets(off, public.id) == []
    end

    test "a delivery that fails says why, and whether to try again", %{config: config} do
      {:ok, _} = Webhooks.add("webhook", "Ours", "https://ours.test/hook")
      entry = entry!("Exports", %{published_at: minutes(-1)})
      hook = id_of("Ours")
      job = %{"job" => "webhook", "entry_id" => entry.id, "hook_id" => hook}

      stub(500)
      assert {:error, {:status, 500}} = Webhooks.deliver(config, entry.id, hook)
      assert {:error, {:status, 500}} = Tayori.Jobs.perform(config, job)

      stub(410)
      assert {:cancel, {:status, 410}} = Tayori.Jobs.perform(config, job)

      stub(429)
      assert {:error, {:status, 429}} = Tayori.Jobs.perform(config, job)

      Req.Test.stub(Tayori.Webhooks, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               Tayori.Jobs.perform(config, job)
    end

    test "a place removed or an entry deleted since is nothing to tell", %{config: config} do
      stub()
      {:ok, _} = Webhooks.add("webhook", "Ours", "https://ours.test/hook")
      entry = entry!("Exports", %{published_at: minutes(-1)})
      hook = id_of("Ours")

      assert :ok = Webhooks.deliver(config, entry.id, "removed")
      {:ok, _} = Entries.delete(entry)
      assert :ok = Webhooks.deliver(config, entry.id, hook)
      refute_received {:request, _, _}
    end

    test "a test message tells each kind of place that it is connected" do
      stub()
      {:ok, secret} = Webhooks.add("webhook", "Ours", "https://ours.test/hook")
      {:ok, _} = Webhooks.add("slack", "Slack", "https://hooks.slack.test/x")

      assert :ok = Webhooks.test(id_of("Ours"))
      assert_received {:request, conn, body}
      assert JSON.decode!(body) == %{"event" => "test", "entry" => nil}
      signature = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
      assert Plug.Conn.get_req_header(conn, "x-tayori-signature") == ["sha256=" <> signature]

      assert :ok = Webhooks.test(id_of("Slack"))
      assert_received {:request, _conn, body}
      assert %{"text" => "Tayori is connected" <> _} = JSON.decode!(body)

      assert {:error, :not_found} = Webhooks.test("unknown")

      stub(404)
      assert {:error, {:status, 404}} = Webhooks.test(id_of("Slack"))
    end

    test "a publication tells each place, from a task without Oban", %{config: config} do
      stub()
      {:ok, _} = Webhooks.add("slack", "Slack", "https://hooks.slack.test/x")
      {:ok, _} = Webhooks.add("webhook", "Ours", "https://ours.test/hook")

      entry!("Exports", %{published_at: minutes(-1)})
      Tayori.Scheduler.announce_due(config)

      assert_receive {:request, %{host: "hooks.slack.test"}, _body}, 1_000
      assert_receive {:request, %{host: "ours.test"}, _body}, 1_000
    end

    test "with Oban, each place to tell is a job of its own", %{config: config, repo: repo} do
      {:ok, _} = Webhooks.add("slack", "Slack", "https://hooks.slack.test/x")
      {:ok, _} = Webhooks.add("webhook", "Ours", "https://ours.test/hook")

      oban =
        if repo == TayoriTest.SQLiteRepo, do: TayoriTest.SQLiteOban, else: TayoriTest.PostgresOban

      put_config(config, oban: %{name: oban, queue: :default})

      entry = entry!("Pro", %{published_at: minutes(-1), segments: ["plan:pro"]})
      Tayori.Test.announce!()

      engine = if repo == TayoriTest.SQLiteRepo, do: Oban.Engines.Lite, else: Oban.Engines.Basic

      # What the announcement sends; the entry's own job is its announcement.
      assert [%{args: args, max_attempts: 8}] =
               Oban.Testing.all_enqueued(repo: repo, engine: engine, worker: Tayori.Worker)
               |> Enum.reject(&(&1.args["job"] == "announce"))

      assert args == %{"job" => "webhook", "entry_id" => entry.id, "hook_id" => id_of("Ours")}
    end

    test "the name of a place, for the logs" do
      {:ok, _} = Webhooks.add("slack", "Slack", "https://hooks.slack.test/x")
      assert Webhooks.name(id_of("Slack")) == "Slack"
      assert Webhooks.name("unknown") == "unknown"
    end
  end
end
