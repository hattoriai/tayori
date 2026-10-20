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
      import TayoriTest.DataCase, only: [entry!: 1, entry!: 2, minutes: 1]
      import TayoriTest.ConnCase

      alias Tayori.{Entries, Entry, Reader}

      @endpoint TayoriTest.Endpoint
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
