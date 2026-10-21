defmodule Tayori.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/hattoriai/tayori"

  # TAYORI_OLDEST=1 resolves the oldest Phoenix and LiveView that Tayori
  # supports, for the CI job that tests them.
  @oldest System.get_env("TAYORI_OLDEST") in ["1", "true"]

  # The bundles, built by mix tayori.build.
  @bundles ~w(
    priv/static/tayori.esm.js
    priv/static/tayori.cjs.js
    priv/static/tayori.css
    priv/static/tayori-sumi.css
    priv/static/tayori-admin.js
    priv/static/tayori-admin.css
  )

  def project do
    [
      app: :tayori,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # For the code reloader of the development server (dev.exs). The
      # listener is Phoenix 1.8's, so the oldest versions go without it.
      listeners: if(@oldest, do: [], else: [Phoenix.CodeReloader]),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :esbuild, :req_llm, :sake],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/project.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      package: package(),
      docs: docs(),
      description: description(),
      name: "Tayori",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      # The entries live in the app's database, on PostgreSQL or SQLite.
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.22", only: [:dev, :test]},
      {:esbuild, "~> 0.10", only: :dev, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # The body of an entry, and its editor in the admin.
      {:kotoba, "~> 0.5"},
      # The publication date's picker in the admin.
      {:koyomi, "~> 0.2"},
      {:lazy_html, "~> 0.1", only: :test},
      # The admin's forms of Ecto changesets; every Phoenix app with Ecto
      # has it.
      {:phoenix_ecto, "~> 4.6"},
      # The mounts in the app's router, their assets and the migrations.
      # 0.2.3 compiles the installer in an app without Igniter.
      {:phoenix_mountable, "~> 0.2.3"},
      {:igniter, "~> 0.6", optional: true},
      {:phoenix, if(@oldest, do: "~> 1.7.14", else: "~> 1.7.14 or ~> 1.8")},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, if(@oldest, do: "~> 1.1.0", else: "~> 1.1")},
      {:postgrex, "~> 0.19", only: [:dev, :test]},
      # The drafts written with AI, with the key an admin gives: any
      # provider ReqLLM knows. Without it, the admin has no AI.
      {:req_llm, "~> 1.6", optional: true},
      # Emails to the subscribers (the :subscriptions feature), with the
      # app's own mailer, and webhooks (the :webhooks feature).
      {:swoosh, "~> 1.17", optional: true},
      {:req, "~> 0.5", optional: true},
      # The emails, webhooks and notifier calls of a publication as jobs,
      # with retries that survive a deploy, when the app runs Oban.
      {:oban, "~> 2.19", optional: true},
      {:telemetry, "~> 1.0"},
      # The time zones of the development server's date picker.
      {:tz, "~> 0.28", only: [:dev, :test]},
      # The MCP server, Tayori.MCP, mounted in the app's own.
      {:sake, "~> 0.4.3", optional: true}
    ]
  end

  defp description do
    "Product news for Phoenix: a changelog with an admin to write it, news in the app for LiveView and any frontend, a public page and feeds, and drafts written with AI."
  end

  defp package do
    [
      name: "tayori",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # The bundle files by name: other build output in priv/static never
      # goes into the package.
      files: ~w(
        lib
        priv/static/tayori.esm.js
        priv/static/tayori.cjs.js
        priv/static/tayori.css
        priv/static/tayori-sumi.css
        priv/static/tayori-admin.js
        priv/static/tayori-admin.css
        package.json
        mix.exs
        .formatter.exs
        guides
        README.md
        CHANGELOG.md
        LICENSE
        NOTICE
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      # The banner of the README, at the same relative path in the docs.
      assets: %{"media" => "media"},
      extras: [
        "README.md",
        "guides/quickstart.md",
        "guides/admin.md",
        "guides/readers.md",
        "guides/in_app.md",
        "guides/any_frontend.md",
        "guides/public_page.md",
        "guides/features.md",
        "guides/ai.md",
        "guides/automation.md",
        "guides/mcp.md",
        "guides/notifications.md",
        "guides/testing.md",
        "guides/theming.md",
        "guides/limits.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "SECURITY.md"
      ],
      groups_for_extras: [
        Guides: [
          "guides/quickstart.md",
          "guides/admin.md",
          "guides/readers.md",
          "guides/in_app.md",
          "guides/any_frontend.md",
          "guides/public_page.md",
          "guides/features.md",
          "guides/ai.md",
          "guides/automation.md",
          "guides/mcp.md",
          "guides/notifications.md",
          "guides/testing.md",
          "guides/theming.md"
        ],
        Reference: ["guides/limits.md"]
      ],
      groups_for_modules: [
        News: [
          Tayori,
          Tayori.Config,
          Tayori.Entries,
          Tayori.Entry,
          Tayori.Translation,
          Tayori.Reader,
          Tayori.Resolver
        ],
        "In the app": [
          Tayori.Live,
          Tayori.Live.State,
          Tayori.Components,
          Tayori.Messages,
          Tayori.Locales
        ],
        Mounting: [Tayori.Router, Tayori.API, Tayori.Embed, Tayori.Page],
        Publishing: [Tayori.Notifier, Tayori.Jobs, Tayori.Worker],
        Database: [Tayori.Migrations],
        AI: [Tayori.AI],
        MCP: [Tayori.MCP],
        Testing: [Tayori.Test]
      ]
    ]
  end

  defp placeholder_bundles(_args) do
    for bundle <- @bundles, not File.exists?(bundle) do
      File.mkdir_p!(Path.dirname(bundle))
      File.touch!(bundle)
    end
  end

  defp build_missing_bundles(_args) do
    if not Enum.all?(@bundles, &File.exists?/1) do
      Mix.shell().info("Building the bundles (mix tayori.build)")

      if Mix.shell().cmd("mix tayori.build") != 0 do
        Mix.raise("mix tayori.build failed")
      end
    end
  end

  # The browser tests need their npm packages; `npm ci` runs once.
  defp e2e_deps(_args) do
    unless File.dir?("e2e/node_modules") do
      Mix.Task.run("cmd", ~w(--cd e2e npm ci))
    end
  end

  defp aliases do
    [
      "assets.build": ["tayori.build"],
      # The router embeds the bundles when it compiles, and mix tayori.build
      # compiles Tayori first: in a fresh checkout, empty files let it.
      "tayori.build": [&placeholder_bundles/1, "tayori.build"],
      # The bundles are built in a mix of their own when any is missing, so
      # that this one compiles the router with them.
      dev: [&build_missing_bundles/1, "run --no-halt dev.exs"],
      "test.e2e": [&e2e_deps/1, "cmd --cd e2e npm test"],
      "test.js": ["cmd --cd assets npm test"],
      # The compile and the asset build run in a child VM, as in Kotoba,
      # Koyomi and Jumon: once anything compiles in this VM, Mix no longer
      # finds the tasks of the Hex archive. The check refuses a priv/static
      # with anything but the bundle files.
      release: [
        "cmd mix tayori.build",
        "cmd mix tayori.release_check",
        "hex.publish --yes",
        "cmd git tag v#{@version} -f",
        "cmd git push",
        "cmd git push --tags"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
