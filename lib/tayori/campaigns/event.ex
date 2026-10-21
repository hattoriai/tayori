defmodule Tayori.Campaigns.Event do
  @moduledoc """
  Something a person did, as the app tracks it (`Tayori.track/3`): the
  person's id, the event's name, what the app adds to it, and when.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          person: String.t() | nil,
          name: String.t() | nil,
          meta: map() | nil,
          occurred_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tayori_events" do
    field :person, :string
    field :name, :string
    field :meta, :map
    field :occurred_at, :utc_datetime_usec
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:person, :name, :meta, :occurred_at])
    |> validate_required([:person, :name, :occurred_at])
    |> validate_length(:person, max: 255)
    |> validate_length(:name, max: 64)
  end
end
