defmodule Tayori.Campaigns.Segment do
  @moduledoc """
  A saved condition on the app's people (`Tayori.Conditions`), with a
  name: "Pro users", "Signed up this week". A campaign's audience, goal
  or skip can name it, and a condition can be in or not in it.

  `:count` is not stored: `Tayori.Campaigns.Segments.list/1` sets it on
  request.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          condition: map() | nil,
          count: non_neg_integer() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tayori_segments" do
    field :name, :string
    field :description, :string
    field :condition, :map, default: %{"all" => []}
    field :count, :integer, virtual: true
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  # The condition is checked against the audience's attributes, and must
  # not lead back to the segment.
  def changeset(segment, attrs, attributes) do
    segment
    |> cast(attrs, [:name, :description, :condition])
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
    |> validate_length(:description, max: 2000)
    |> Tayori.Campaigns.Schema.validate_condition(:condition, attributes,
      required: true,
      segment_id: segment.id
    )
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
