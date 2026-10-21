defmodule TayoriTest.ConnCase do
  @moduledoc """
  Tests of the admin and the readers' pages through the test endpoint,
  on SQLite (the database tests run on both, see TayoriTest.DataCase).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import TayoriTest.DataCase, only: [entry!: 1, entry!: 2, minutes: 1, put_config: 2]
      import TayoriTest.ConnCase

      alias Tayori.{Entries, Entry, Reader}

      @endpoint TayoriTest.Host.Endpoint
    end
  end

  setup do
    {:ok, ctx} = TayoriTest.DataCase.checkout(TayoriTest.SQLiteRepo)
    {:ok, Keyword.put(ctx, :conn, Phoenix.ConnTest.build_conn())}
  end

  @doc "A conn with these values in the session."
  def with_session(conn, session) do
    Phoenix.ConnTest.init_test_session(conn, session)
  end

  @doc "A conn of an admin with a role: admin, viewer or banned."
  def as_admin(conn, role \\ "admin") do
    with_session(conn, %{"admin" => %{"role" => role, "id" => 7, "name" => "Hanzo"}})
  end
end

defmodule TayoriTest.LiveCase do
  @moduledoc """
  Tests of the admin's pages on both databases: write them in
  `for_each_repo do ... end` (TayoriTest.DataCase), with a conn in the
  context.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import TayoriTest.DataCase
      import TayoriTest.ConnCase, only: [with_session: 2, as_admin: 1, as_admin: 2]
      import TayoriTest.LiveCase, only: [campaigns_describe: 2]

      @endpoint TayoriTest.Host.Endpoint
    end
  end

  @doc """
  A describe with the campaigns on, once for each repo (SQLite, and
  PostgreSQL tagged :postgres).
  """
  defmacro campaigns_describe(name, do: block) do
    for {db, repo, tags} <- [
          {"SQLite", TayoriTest.SQLiteRepo, []},
          {"PostgreSQL", TayoriTest.PostgresRepo, [postgres: true]}
        ] do
      quote do
        describe unquote("#{name} (#{db})") do
          @describetag unquote(tags)
          setup do: TayoriTest.DataCase.checkout(unquote(repo))
          setup :campaigns
          unquote(block)
        end
      end
    end
  end

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
