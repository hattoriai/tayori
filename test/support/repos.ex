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
  def up, do: Tayori.Migrations.up(version: 1)
  def down, do: Tayori.Migrations.down(to: 0)
end

defmodule TayoriTest.ObanMigration do
  @moduledoc false
  use Ecto.Migration
  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down()
end
