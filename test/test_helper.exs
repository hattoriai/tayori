{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: TayoriTest.PubSub)
{:ok, _pid} = TayoriTest.Endpoint.start_link()

# The entries in a database: SQLite always, PostgreSQL when it is
# reachable (TAYORI_TEST_DATABASE_URL, or postgres:postgres@localhost).
File.mkdir_p!(Path.expand("../tmp", __DIR__))

migrate = fn repo ->
  Ecto.Migrator.run(repo, [{0, TayoriTest.Migration}], :up, all: true, log: false)
end

_ = Ecto.Adapters.SQLite3.storage_up(TayoriTest.SQLiteRepo.config())
{:ok, _pid} = TayoriTest.SQLiteRepo.start_link()
migrate.(TayoriTest.SQLiteRepo)
Ecto.Adapters.SQL.Sandbox.mode(TayoriTest.SQLiteRepo, :manual)

postgres? =
  case Ecto.Adapters.Postgres.storage_up(TayoriTest.PostgresRepo.config()) do
    result when result in [:ok, {:error, :already_up}] ->
      {:ok, _pid} = TayoriTest.PostgresRepo.start_link()
      migrate.(TayoriTest.PostgresRepo)
      Ecto.Adapters.SQL.Sandbox.mode(TayoriTest.PostgresRepo, :manual)
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
