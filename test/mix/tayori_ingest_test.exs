defmodule Mix.Tasks.Tayori.IngestTest do
  use ExUnit.Case

  alias Mix.Tasks.Tayori.Ingest

  @moduletag :tmp_dir
  @url "https://app.test/api/machines/news"

  setup %{tmp_dir: tmp_dir} do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    changelog = Path.join(tmp_dir, "CHANGELOG.md")

    File.write!(changelog, """
    # Changelog

    ## [Unreleased]

    - Not yet.

    ## [1.4.0] - 2026-10-20

    ### Added

    - Exports in two clicks.

    ### Fixed

    - Dates showed a day early in Auckland.
    """)

    news = Path.join(tmp_dir, "news")
    File.mkdir_p!(news)
    File.write!(Path.join(news, "dark-mode.md"), "---\nkind: added\n---\n\nDark mode, at last.\n")

    %{changelog: changelog, news: news}
  end

  # The app's API, as the test stubs it: it tells the test what it got.
  defp stub(answer) do
    test = self()

    Req.Test.stub(Ingest, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn, JSON.decode!(body)})
      answer.(conn, JSON.decode!(body))
    end)
  end

  defp counts(conn, %{"changes" => changes}) do
    Req.Test.json(Plug.Conn.put_status(conn, 201), %{
      added: length(changes),
      existing: 0,
      errors: []
    })
  end

  defp infos do
    Stream.repeatedly(fn ->
      receive do
        {:mix_shell, :info, [line]} -> line
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
  end

  describe "from CI" do
    test "sends the changelog's and the fragments' changes with the token", ctx do
      stub(&counts/2)

      Ingest.run(
        ~w(--url #{@url}/ --token tyi_secret --changelog #{ctx.changelog} --fragments #{ctx.news})
      )

      assert_received {:request, conn, %{"changes" => changes}}
      assert conn.method == "POST"
      assert conn.request_path == "/api/machines/news/changes"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tyi_secret"]

      assert [
               %{"source" => "changelog", "version" => "1.4.0", "kind" => "added"},
               %{"source" => "changelog", "kind" => "fixed"},
               %{
                 "source" => "fragments",
                 "ref" => "dark-mode.md",
                 "title" => "Dark mode, at last"
               }
             ] = changes

      assert infos() == ["Sent 3 changes: 3 new, 0 there already"]
    end

    test "the token from the environment, one source for all, batches of 500", ctx do
      stub(&counts/2)
      System.put_env("TAYORI_INGEST_TOKEN", "tyi_env")
      on_exit(fn -> System.delete_env("TAYORI_INGEST_TOKEN") end)

      items = Enum.map_join(1..501, "\n", &"- Change #{&1}.")
      File.write!(ctx.changelog, "## [2.0.0] - 2026-10-20\n\n### Added\n\n#{items}\n")

      Ingest.run(~w(--url #{@url} --changelog #{ctx.changelog} --source ci))

      assert_received {:request, conn, %{"changes" => first}}
      assert_received {:request, _conn, %{"changes" => [last]}}
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tyi_env"]
      assert length(first) == 500
      assert Enum.all?(first, &(&1["source"] == "ci"))
      assert last["title"] == "Change 501"
    end

    test "fails when a change is invalid, naming it by its ref", ctx do
      stub(fn conn, _body ->
        Req.Test.json(Plug.Conn.put_status(conn, 200), %{
          added: 0,
          existing: 2,
          errors: [%{index: 0, errors: %{title: ["should be at most 255 character(s)"]}}]
        })
      end)

      assert_raise Mix.Error, "1 changes were not added", fn ->
        Ingest.run(~w(--url #{@url} --token t --fragments #{ctx.news}))
      end

      assert_received {:mix_shell, :error,
                       ["dark-mode.md: title should be at most 255 character(s)"]}
    end

    test "fails when the app refuses, or cannot be reached", ctx do
      stub(fn conn, _body ->
        Req.Test.json(Plug.Conn.put_status(conn, 401), %{error: "unauthorized"})
      end)

      assert_raise Mix.Error, ~r/answered 401/, fn ->
        Ingest.run(~w(--url #{@url} --token wrong --changelog #{ctx.changelog}))
      end

      Req.Test.stub(Ingest, &Req.Test.transport_error(&1, :econnrefused))

      assert_raise Mix.Error, ~r/Cannot reach/, fn ->
        Ingest.run(~w(--url #{@url} --token t --changelog #{ctx.changelog}))
      end
    end

    test "needs a token, something to send, and files that are there", ctx do
      assert_raise Mix.Error, ~r/needs the ingest token/, fn ->
        Ingest.run(~w(--url #{@url} --changelog #{ctx.changelog}))
      end

      assert_raise Mix.Error, ~r/Give --changelog, --fragments or both/, fn ->
        Ingest.run(~w(--url #{@url} --token t))
      end

      assert_raise Mix.Error, ~r/Cannot read the changelog/, fn ->
        Ingest.run(~w(--url #{@url} --token t --changelog #{ctx.tmp_dir}/NOPE.md))
      end

      assert_raise Mix.Error, ~r/--changelog needs --url/, fn ->
        Ingest.run(~w(--changelog #{ctx.changelog}))
      end

      assert_raise Mix.Error, ~r/Unknown arguments: --nope/, fn ->
        Ingest.run(~w(--nope))
      end
    end
  end
end

defmodule Mix.Tasks.Tayori.IngestAppTest do
  use TayoriTest.DataCase

  alias Mix.Tasks.Tayori.Ingest
  alias Tayori.Inbox

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    changelog = Path.join(tmp_dir, "CHANGELOG.md")
    File.write!(changelog, "## [1.0.0] - 2026-10-01\n\n### Added\n\n- Exports.\n- Search.\n")
    %{changelog: changelog}
  end

  for_each_repo do
    test "in the app: reads the sources of the config, and prints each", ctx do
      put_config(ctx.config,
        inbox: [
          sources: [
            {Tayori.Sources.Changelog, path: ctx.changelog},
            {Tayori.Sources.Fragments, path: Path.join(ctx.tmp_dir, "news")}
          ]
        ]
      )

      File.mkdir_p!(Path.join(ctx.tmp_dir, "news"))
      Ingest.run([])

      assert_received {:mix_shell, :info, ["changelog: 2 new, 0 there already"]}
      assert_received {:mix_shell, :info, ["fragments: 0 new, 0 there already"]}
      assert length(Inbox.list(source: "changelog")) == 2

      Ingest.run([])
      assert_received {:mix_shell, :info, ["changelog: 0 new, 2 there already"]}
    end

    test "in the app: fails when a source cannot be read", ctx do
      put_config(ctx.config,
        inbox: [sources: [{Tayori.Sources.Changelog, path: ctx.tmp_dir <> "/NOPE.md"}]]
      )

      ExUnit.CaptureLog.capture_log(fn ->
        assert_raise Mix.Error, "Tayori could not read changelog", fn -> Ingest.run([]) end
      end)

      assert_received {:mix_shell, :error, ["changelog: {:file, " <> _]}
    end

    test "in the app, with no sources", ctx do
      put_config(ctx.config, inbox: [])
      Ingest.run([])
      assert_received {:mix_shell, :info, ["The :inbox config has no sources"]}
    end
  end
end
