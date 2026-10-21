defmodule TayoriTest.SQLiteRepo do
  @moduledoc "A repo on SQLite."
  use Ecto.Repo, otp_app: :tayori, adapter: Ecto.Adapters.SQLite3
end

defmodule TayoriTest.PostgresRepo do
  @moduledoc "A repo on PostgreSQL."
  use Ecto.Repo, otp_app: :tayori, adapter: Ecto.Adapters.Postgres
end

defmodule TayoriTest.MigrationsRepo do
  @moduledoc "A repo on SQLite of its own, which the checks of the migrations empty."
  use Ecto.Repo, otp_app: :tayori, adapter: Ecto.Adapters.SQLite3
end

defmodule TayoriTest.PostgresMigrationsRepo do
  @moduledoc "A repo on PostgreSQL with no sandbox, for the checks of the migrations in a prefix."
  use Ecto.Repo, otp_app: :tayori, adapter: Ecto.Adapters.Postgres
end

defmodule TayoriTest.Migration do
  @moduledoc false
  use Ecto.Migration
  def up, do: Tayori.Migrations.up(version: 2)
  def down, do: Tayori.Migrations.down(to: 0)
end

defmodule TayoriTest.AppMigration do
  @moduledoc false
  # The tables of the app of the tests, its people, their photos and
  # stories, for the campaigns' audience (TayoriTest.Audience). Tayori is
  # at version 2 first: a database made before it had version 1 only.
  use Ecto.Migration

  def up do
    Tayori.Migrations.up(version: 2)

    create table(:test_people) do
      add :name, :string
      add :email, :string
      add :locale, :string
      add :plan, :string
      add :visits, :integer
      add :born_on, :date
      add :closed_at, :utc_datetime_usec
      add :optional_emails, :boolean, null: false, default: true
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create table(:test_photos) do
      add :person_id, references(:test_people, on_delete: :delete_all), null: false
    end

    create table(:test_stories) do
      add :person_id, references(:test_people, on_delete: :delete_all), null: false
      add :published_at, :utc_datetime_usec
    end
  end

  def down do
    drop table(:test_stories)
    drop table(:test_photos)
    drop table(:test_people)
  end
end

defmodule TayoriTest.ObanMigration do
  @moduledoc false
  use Ecto.Migration
  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down()
end
