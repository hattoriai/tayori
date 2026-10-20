defmodule Mix.Tasks.Tayori.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @app_js """
  import "phoenix_html"
  import {Socket} from "phoenix"
  import {LiveSocket} from "phoenix_live_view"

  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
  const liveSocket = new LiveSocket("/live", Socket, {
    params: {_csrf_token: csrfToken},
    hooks: {},
  })

  liveSocket.connect()
  """

  @app_css """
  @import "tailwindcss" source(none);
  @source "../css";
  """

  @router """
  defmodule TestWeb.Router do
    use Phoenix.Router

    pipeline :browser do
      plug :accepts, ["html"]
    end

    scope "/", TestWeb do
      pipe_through :browser
    end
  end
  """

  @application """
  defmodule Test.Application do
    use Application

    def start(_type, _args) do
      children = [
        Test.Repo,
        {Phoenix.PubSub, name: Test.PubSub},
        TestWeb.Endpoint
      ]

      Supervisor.start_link(children, strategy: :one_for_one, name: Test.Supervisor)
    end
  end
  """

  @mix_exs """
  defmodule Test.MixProject do
    use Mix.Project

    def project, do: [app: :test, version: "0.1.0", deps: deps()]

    def application, do: [mod: {Test.Application, []}, extra_applications: [:logger]]

    defp deps, do: []
  end
  """

  # A Phoenix app's files, written here rather than by phx_test_project/1,
  # which needs the phx_new archive.
  defp install(files \\ %{}) do
    [
      files:
        Map.merge(
          %{
            ".formatter.exs" =>
              "[import_deps: [:phoenix], inputs: [\"{lib,test}/**/*.{ex,exs}\"]]\n",
            "lib/test_web/router.ex" => @router,
            "mix.exs" => @mix_exs,
            "lib/test/application.ex" => @application,
            "assets/js/app.js" => @app_js,
            "assets/css/app.css" => @app_css
          },
          files
        ),
      app_name: :test
    ]
    |> test_project()
    |> Igniter.compose_task(Mix.Tasks.Tayori.Install, [])
  end

  defp file(igniter, path) do
    igniter
    |> apply_igniter!()
    |> Map.fetch!(:rewrite)
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  test "mounts the admin and the page in the router" do
    router = install() |> file("lib/test_web/router.ex")

    assert router =~ "import Tayori.Router"

    assert router =~
             ~r/scope "\/admin" do.*tayori_admin[ (]"\/news", resolver: TestWeb.TayoriResolver/s

    assert router =~ ~r/tayori_page[ (]"\/changelog"/
    refute router =~ "import Tayori.Router.Page"
  end

  test "adds the hook and the style sheets" do
    igniter = install()

    assert file(igniter, "assets/js/app.js") =~ ~s(import { Tayori } from "tayori")
    assert file(igniter, "assets/js/app.js") =~ "hooks: {Tayori}"

    css = file(igniter, "assets/css/app.css")
    assert css =~ ~r/@import "[^"]*kotoba\/priv\/static\/kotoba.css";/
    assert css =~ ~r/@import "[^"]*tayori\/priv\/static\/tayori.css";/
    assert css =~ ~r/\/\* @import "[^"]*tayori-sumi.css"; \*\//
  end

  test "starts Tayori after the repo and the PubSub" do
    application = install() |> file("lib/test/application.ex")

    assert application =~ ~r/name: Test.PubSub\},.*\{Tayori,/s
    assert application =~ "repo: Test.Repo"
    assert application =~ "pubsub: Test.PubSub"

    assert application =~
             "Application.fetch_env!(:test, TestWeb.Endpoint)[:secret_key_base]"
  end

  test "gives Tayori the app's Oban, when it has one" do
    refute install() |> file("lib/test/application.ex") =~ "oban:"

    mix_exs =
      String.replace(@mix_exs, "defp deps, do: []", ~s(defp deps, do: [{:oban, "~> 2.19"}]))

    application =
      install(%{"mix.exs" => mix_exs, "lib/test/application.ex" => with_oban()})
      |> file("lib/test/application.ex")

    assert application =~ "oban: Oban"
    assert application =~ ~r/\{Oban, .*\{Tayori,/s
  end

  defp with_oban do
    String.replace(
      @application,
      "{Phoenix.PubSub, name: Test.PubSub},",
      "{Phoenix.PubSub, name: Test.PubSub},\n        {Oban, Application.fetch_env!(:test, Oban)},"
    )
  end

  test "writes the resolver, which lets no one in" do
    igniter = install()

    assert_creates(igniter, "lib/test_web/tayori_resolver.ex")
    resolver = file(igniter, "lib/test_web/tayori_resolver.ex")
    assert resolver =~ "defmodule TestWeb.TayoriResolver"
    assert resolver =~ "def resolve_access(_user), do: :forbidden"
    assert resolver =~ ~S|id: "user:#{user.id}"|
  end

  test "leaves the app's own resolver alone" do
    install(%{
      "lib/test_web/tayori_resolver.ex" => "defmodule TestWeb.TayoriResolver do\nend\n"
    })
    |> refute_creates("lib/test_web/tayori_resolver.ex")
  end

  test "changes nothing the second time" do
    install()
    |> apply_igniter!()
    |> Igniter.compose_task(Mix.Tasks.Tayori.Install, [])
    |> assert_unchanged()
  end
end
