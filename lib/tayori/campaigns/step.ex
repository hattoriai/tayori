defmodule Tayori.Campaigns.Step do
  @moduledoc """
  A letter of a campaign and when it goes: `:wait` minutes after the
  person entered the sequence (0 for a broadcast's one step), unless
  `:skip_if` (a condition, `Tayori.Conditions`) matches them when the
  step's time comes. The steps go in the order of their wait, then of
  their `:position`. The letter is in one or more languages
  (`Tayori.Campaigns.Letter`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tayori.Campaigns.{Campaign, Letter, Schema}

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          campaign_id: Ecto.UUID.t() | nil,
          position: integer(),
          wait: non_neg_integer(),
          skip_if: map() | nil,
          letters: [Letter.t()] | Ecto.Association.NotLoaded.t()
        }

  @wait_taken "another step goes at this time"

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tayori_campaign_steps" do
    belongs_to :campaign, Campaign
    field :position, :integer, default: 0
    field :wait, :integer, default: 0
    field :skip_if, :map
    has_many :letters, Letter, on_replace: :delete, preload_order: [asc: :locale]
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  # Two steps of a sequence at one time would be one: the context checks
  # it, and the unique index of (campaign_id, wait) when two writes come
  # at once.
  def wait_taken, do: @wait_taken

  @doc false
  def changeset(step, attrs, attributes, locales) do
    step
    |> cast(attrs, [:position, :wait, :skip_if])
    |> validate_required([:position, :wait])
    |> validate_number(:wait, greater_than_or_equal_to: 0)
    |> unique_constraint(:wait,
      name: :tayori_campaign_steps_campaign_id_wait_index,
      message: @wait_taken
    )
    |> Schema.validate_condition(:skip_if, attributes)
    |> cast_assoc(:letters, with: &Letter.changeset(&1, &2, locales))
  end
end
