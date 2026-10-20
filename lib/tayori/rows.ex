defmodule Tayori.Reaction do
  @moduledoc false
  # A reader's reaction to an entry (Tayori.Reactions).
  use Ecto.Schema

  @primary_key false
  schema "tayori_reactions" do
    field :entry_id, :binary_id, primary_key: true
    field :reader, :string, primary_key: true
    field :emoji, :string, primary_key: true
    field :inserted_at, :utc_datetime_usec
  end
end

defmodule Tayori.View do
  @moduledoc false
  # The views of an entry by a reader, from a source, on a day (Tayori.Views).
  use Ecto.Schema

  @primary_key false
  schema "tayori_views" do
    field :entry_id, :binary_id, primary_key: true
    field :reader, :string, primary_key: true
    field :source, :string, primary_key: true
    field :day, :date, primary_key: true
    field :count, :integer, default: 1
  end
end

defmodule Tayori.Dismissal do
  @moduledoc false
  # An announcement a reader dismissed (Tayori.Announcements).
  use Ecto.Schema

  @primary_key false
  schema "tayori_dismissals" do
    field :reader, :string, primary_key: true
    field :entry_id, :binary_id, primary_key: true
    field :inserted_at, :utc_datetime_usec
  end
end
