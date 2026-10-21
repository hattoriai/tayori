{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: TayoriTest.PubSub)
{:ok, _pid} = Task.Supervisor.start_link(name: Tayori.TaskSupervisor)
Application.put_env(:tayori, :ai_adapter, TayoriTest.FakeAI)
{:ok, _pid} = TayoriTest.Host.start()

# The entries in a database: SQLite always, PostgreSQL when it is
# reachable (TAYORI_TEST_DATABASE_URL, or postgres:postgres@localhost).
File.mkdir_p!(Path.expand("../tmp", __DIR__))

# The app's own tables (TayoriTest.AppMigration) come after Tayori's.
migrations = [
  {0, TayoriTest.Migration},
  {1, TayoriTest.ObanMigration},
  {2, TayoriTest.AppMigration}
]

migrate = fn repo -> Ecto.Migrator.run(repo, migrations, :up, all: true, log: false) end

_ = Ecto.Adapters.SQLite3.storage_up(TayoriTest.SQLiteRepo.config())
{:ok, _pid} = TayoriTest.SQLiteRepo.start_link()
migrate.(TayoriTest.SQLiteRepo)
Ecto.Adapters.SQL.Sandbox.mode(TayoriTest.SQLiteRepo, :manual)
{:ok, _pid} = TayoriTest.MigrationsRepo.start_link()

# An Oban for each repo, which keeps its jobs for the tests to run.
{:ok, _pid} =
  Oban.start_link(
    name: TayoriTest.SQLiteOban,
    repo: TayoriTest.SQLiteRepo,
    engine: Oban.Engines.Lite,
    testing: :manual
  )

postgres? =
  case Ecto.Adapters.Postgres.storage_up(TayoriTest.PostgresRepo.config()) do
    result when result in [:ok, {:error, :already_up}] ->
      {:ok, _pid} = TayoriTest.PostgresRepo.start_link()
      migrate.(TayoriTest.PostgresRepo)
      Ecto.Adapters.SQL.Sandbox.mode(TayoriTest.PostgresRepo, :manual)
      {:ok, _pid} = TayoriTest.PostgresMigrationsRepo.start_link()

      {:ok, _pid} =
        Oban.start_link(
          name: TayoriTest.PostgresOban,
          repo: TayoriTest.PostgresRepo,
          testing: :manual
        )

      true

    {:error, reason} ->
      IO.puts(
        "PostgreSQL is not reachable (#{inspect(reason)}): the :postgres tests are excluded"
      )

      false
  end

# The :build tests run `mix tayori.build` (npm and network on the first
# run) and `mix hex.build`: `mix test --include build`.
ExUnit.start(exclude: [:build] ++ if(postgres?, do: [], else: [:postgres]))
