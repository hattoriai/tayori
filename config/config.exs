import Config

if config_env() == :dev do
  # The bundles. The news bundle (the hook and <tayori-news>) leaves
  # Phoenix to the app; the admin bundle is a whole page of its own, with
  # Phoenix, LiveView, Kotoba and Koyomi in it, so it reads deps/.
  esbuild_args = ~w(
    src/index.ts
    --bundle
    --minify
    --target=es2020
    --external:phoenix
    --external:phoenix_live_view
  )

  config :esbuild,
    version: "0.28.2",
    tayori_esm: [
      args: esbuild_args ++ ~w(--format=esm --outfile=../priv/static/tayori.esm.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ],
    tayori_cjs: [
      args: esbuild_args ++ ~w(--format=cjs --outfile=../priv/static/tayori.cjs.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ],
    tayori_admin: [
      args: ~w(
        src/admin.ts
        --bundle
        --minify
        --target=es2020
        --format=iife
        --outfile=../priv/static/tayori-admin.js
      ),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]
end

# Swoosh is optional, for the emails of the :subscriptions feature: the
# app gives its own mailer, and Tayori needs no HTTP client of Swoosh's.
config :swoosh, :api_client, false

if config_env() == :test do
  config :logger, level: :warning
  config :phoenix, :json_library, JSON

  # The entries, tested with both adapters. The PostgreSQL tests are
  # tagged :postgres, and run when the database is reachable (see
  # test/test_helper.exs).
  config :tayori, TayoriTest.SQLiteRepo,
    database: Path.expand("../tmp/tayori_test.sqlite3", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5

  config :tayori, TayoriTest.PostgresRepo,
    url:
      System.get_env(
        "TAYORI_TEST_DATABASE_URL",
        "ecto://postgres:postgres@localhost/tayori_test"
      ),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5

  config :tayori, ecto_repos: [TayoriTest.SQLiteRepo, TayoriTest.PostgresRepo]

  config :tayori, TayoriTest.Mailer, adapter: Swoosh.Adapters.Test

  # A forgotten version of Tayori.Migrations fails the tests.
  config :phoenix_mountable, pending_migrations: :raise
end
