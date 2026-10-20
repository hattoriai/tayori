defmodule Mix.Tasks.Tayori.Install do
  @shortdoc "Adds the Tayori hook, style sheet, resolver and migration to a Phoenix app"

  @moduledoc """
  Sets up Tayori in a Phoenix application.

      $ mix tayori.install
      $ mix tayori.install --dry-run

  The task edits two files, and writes two when they are missing:

    * `assets/js/app.js` - adds `import { Tayori } from "tayori"` and puts
      `Tayori` in the `hooks` of the `LiveSocket`. When it cannot find the
      `new LiveSocket(...)` call, or its hooks are not an object or a
      variable, it changes nothing and prints the lines to add.
    * `assets/css/app.css` - adds
      `@import "../../deps/tayori/priv/static/tayori.css";`, and the Sumi
      theme import as a comment. The imports follow the deps directory of
      the project (`Mix.Project.deps_path/0`) when it is not `deps/`, as in
      an umbrella child or with `MIX_DEPS_PATH`. For a path dependency
      (`{:tayori, path: "../tayori"}`), which Mix does not copy into
      `deps/`, the imports point at the dependency's directory instead.

    * `lib/my_app_web/tayori_resolver.ex` - a resolver
      (`MyAppWeb.TayoriResolver`, see `Tayori.Resolver`), which lets no
      one in the admin until you say who your admins are.
    * the migration of Tayori's tables (`mix tayori.gen.migration`).

  Then it prints the esbuild note (the app's esbuild must resolve `tayori`
  through `NODE_PATH`: from `deps/`, or, for a path dependency, from the
  directory that holds it), and the lines to add to the supervision tree,
  the router and the layout.

  The task is idempotent: it does not add what a file already has, and when
  there is nothing to add it says so.

  ## Options

    * `--dry-run` - prints the changes as a diff and writes nothing.
  """

  use Mix.Task

  alias Tayori.Install.Edits

  @js "assets/js/app.js"
  @css "assets/css/app.css"
  @config "config/config.exs"

  @impl Mix.Task
  def run(argv) do
    deps_path = Mix.Project.deps_path()
    install(argv, package_path(Mix.Project.deps_paths(), deps_path), deps_path)
  end

  @doc false
  # The task, with the directory of the Tayori package and the deps
  # directory of the project given.
  @spec install([String.t()], Path.t(), Path.t()) :: :ok
  def install(argv, package, deps_path \\ "deps") do
    {opts, _args} = OptionParser.parse!(argv, strict: [dry_run: :boolean])
    dry_run? = Keyword.get(opts, :dry_run, false)

    css_dir = Edits.relative(package, Path.dirname(@css))

    results = [
      edit(@js, &Edits.app_js/1, Edits.app_js_manual(), dry_run?),
      edit(@css, &Edits.app_css(&1, css_dir), Edits.app_css_manual(css_dir), dry_run?),
      resolver(Mix.Project.config()[:app], dry_run?),
      migration(dry_run?)
    ]

    if Enum.all?(results, &(&1 == :unchanged)) do
      Mix.shell().info("Tayori is already installed. Nothing changed.")
    else
      notes(package, deps_path)
    end
  end

  @doc false
  # Where the Tayori package is, from `Mix.Project.deps_paths/0`: tayori in
  # the deps directory (`Mix.Project.deps_path/0`, which an umbrella child or
  # MIX_DEPS_PATH moves away from deps/), or the directory of a path
  # dependency (`{:tayori, path: "../tayori"}`), which Mix does not copy there.
  @spec package_path(%{optional(atom()) => Path.t()}, Path.t()) :: Path.t()
  def package_path(deps_paths, deps_path \\ "deps") do
    case deps_paths[:tayori] do
      nil -> Path.expand(Path.join(deps_path, "tayori"))
      path -> Path.expand(path)
    end
  end

  @doc false
  # The resolver of the app, written when its file is missing.
  @spec resolver(atom() | nil, boolean()) :: :changed | :unchanged
  def resolver(nil, _dry_run?), do: :unchanged

  def resolver(app, dry_run?) do
    web = Edits.web_module(app)
    path = Path.join(["lib", Macro.underscore(web), "tayori_resolver.ex"])

    cond do
      File.exists?(path) ->
        Mix.shell().info([:green, "* unchanged ", :reset, path, " (it exists)"])
        :unchanged

      dry_run? ->
        Mix.shell().info([:cyan, "* would create ", :reset, path])
        :changed

      true ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Edits.resolver_module(web))
        Mix.shell().info([:green, "* creating ", :reset, path])
        :changed
    end
  end

  # The migration of the tables, by `mix tayori.gen.migration`, which
  # leaves an existing one alone.
  defp migration(true) do
    Mix.shell().info([:cyan, "* would run ", :reset, "mix tayori.gen.migration"])
    :changed
  end

  defp migration(false) do
    if Mix.Project.config()[:app] &&
         Application.get_env(Mix.Project.config()[:app], :ecto_repos, []) != [] do
      case Mix.Tasks.Tayori.Gen.Migration.run([]) do
        :created -> :changed
        :unchanged -> :unchanged
      end
    else
      Mix.shell().info([
        :yellow,
        "* skipping ",
        :reset,
        "the migration (no :ecto_repos); run mix tayori.gen.migration"
      ])

      :unchanged
    end
  end

  defp edit(path, fun, manual, dry_run?) do
    case File.read(path) do
      {:ok, source} ->
        apply_edit(path, source, fun.(source), dry_run?)

      {:error, _reason} ->
        Mix.shell().info([:yellow, "* skipping ", :reset, path, " (not found)"])
        Mix.shell().info(indent(manual))
        :manual
    end
  end

  defp apply_edit(path, _source, :unchanged, _dry_run?) do
    Mix.shell().info([:green, "* unchanged ", :reset, path, " (Tayori is already there)"])
    :unchanged
  end

  defp apply_edit(path, _source, {:manual, text}, _dry_run?) do
    Mix.shell().info([:yellow, "* skipping ", :reset, path, " (add the lines below by hand)"])
    Mix.shell().info(indent(text))
    :manual
  end

  defp apply_edit(path, source, {:changed, new}, true) do
    Mix.shell().info([:cyan, "* would update ", :reset, path])
    Mix.shell().info(Edits.diff(path, source, new))
    :changed
  end

  defp apply_edit(path, source, {:changed, new}, false) do
    File.write!(path, new)
    Mix.shell().info([:green, "* updating ", :reset, path])
    Mix.shell().info(Edits.diff(path, source, new))
    :changed
  end

  defp notes(package, deps_path) do
    config_source =
      case File.read(@config) do
        {:ok, source} -> source
        {:error, _reason} -> ""
      end

    Mix.shell().info("""

    #{esbuild_note(config_source, package, deps_path)}

    Run the migration (mix ecto.migrate), and add Tayori to your supervision
    tree, after the repo and the PubSub:

        {Tayori,
         repo: MyApp.Repo,
         pubsub: MyApp.PubSub,
         secret_key_base: Application.fetch_env!(:my_app, MyAppWeb.Endpoint)[:secret_key_base],
         locales: ["en"]}

    Say who your admins are in lib/my_app_web/tayori_resolver.ex, and mount
    the admin behind your admin pipeline, in the router:

        import Tayori.Router

        scope "/admin" do
          pipe_through [:browser, :require_admin]
          tayori_admin "/news", resolver: MyAppWeb.TayoriResolver
        end

        scope "/" do
          pipe_through :browser
          tayori_page "/changelog"
        end

    Then the news in your LiveViews: {Tayori.Live, MyAppWeb.TayoriResolver} in
    the on_mount of the live_session, after your own hooks, and in the layout:

        <Tayori.Components.news_button tayori={@tayori} />
        <Tayori.Components.news_panel tayori={@tayori} />

    The bodies of the entries are Kotoba content: import kotoba.css too, if
    your app does not already. For the Sumi theme, remove the comment marks
    around the tayori-sumi.css import in assets/css/app.css. For a frontend
    that LiveView does not render, see tayori_api and <tayori-news>.
    """)
  end

  defp esbuild_note(config_source, package, deps_path) do
    if Path.dirname(package) == Path.expand(deps_path) do
      deps = Edits.relative(deps_path, ".")
      from_config = Edits.relative(deps_path, "config")

      resolves? =
        if deps == "deps",
          do: Edits.node_path?(config_source),
          else: Edits.node_path?(config_source, from_config)

      if resolves? do
        "Your esbuild config sets NODE_PATH to #{deps}/, so `import { Tayori } from \"tayori\"` resolves."
      else
        """
        The esbuild profile of your app must resolve `tayori` from #{deps}/. Give it
        NODE_PATH=#{deps} in config/config.exs:

            env: %{"NODE_PATH" => [Path.expand("#{from_config}", __DIR__), Mix.Project.build_path()]}\
        """
      end
    else
      parent = Edits.relative(Path.dirname(package), "config")

      if Edits.node_path?(config_source, parent) do
        "Your esbuild config has the directory of the Tayori path dependency in NODE_PATH, so `import { Tayori } from \"tayori\"` resolves."
      else
        """
        Tayori is a path dependency (#{Edits.relative(package, ".")}), so it is not in deps/.
        The esbuild profile of your app finds `tayori` through NODE_PATH: add the
        directory that holds it to the NODE_PATH in config/config.exs:

            env: %{
              "NODE_PATH" => [
                Path.expand("../deps", __DIR__),
                Path.expand("#{parent}", __DIR__),
                Mix.Project.build_path()
              ]
            }\
        """
      end
    end
  end

  defp indent(text) do
    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> "    " <> line
    end)
  end
end
