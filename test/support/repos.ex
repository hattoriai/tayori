defmodule TayoriTest.SQLiteRepo do
  @moduledoc "A repo on SQLite."
  use Ecto.Repo, otp_app: :tayori, adapter: Ecto.Adapters.SQLite3
end

defmodule TayoriTest.PostgresRepo do
  @moduledoc "A repo on PostgreSQL."
  use Ecto.Repo, otp_app: :tayori, adapter: Ecto.Adapters.Postgres
end

defmodule TayoriTest.Migration do
  @moduledoc false
  use Ecto.Migration
  def up, do: Tayori.Migration.up()
  def down, do: Tayori.Migration.down()
end
