defmodule Tayori.Campaigns.Enrollment do
  @moduledoc """
  A person in a sequence, once: when they entered, and where they are.

    * `:state` - `"active"`, `"completed"` (the goal reached, the steps
      done, or `max_days` passed) or `"exited"` (they left the audience,
      unsubscribed, cannot be emailed, or the sequence was stopped).
    * `:reason` - why it ended: `"goal"`, `"finished"`, `"expired"`,
      `"left"`, `"unsubscribed"`, `"cannot_email"` or `"stopped"`.
    * `:cursor` - the wait of the last step handled, in minutes (-1 at
      entry): the steps after it are still to come.
    * `:next_at` - when it is looked at again; nil while it waits for
      nothing, or is being looked at.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @states ~w(active completed exited)
  @reasons ~w(goal finished expired left unsubscribed cannot_email stopped)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          campaign_id: Ecto.UUID.t() | nil,
          person: String.t() | nil,
          state: String.t(),
          reason: String.t() | nil,
          entered_at: DateTime.t() | nil,
          cursor: integer(),
          next_at: DateTime.t() | nil,
          last_sent_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tayori_enrollments" do
    belongs_to :campaign, Tayori.Campaigns.Campaign
    field :person, :string
    field :state, :string, default: "active"
    field :reason, :string
    field :entered_at, :utc_datetime_usec
    field :cursor, :integer, default: -1
    field :next_at, :utc_datetime_usec
    field :last_sent_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The states of an enrollment."
  @spec states() :: [String.t()]
  def states, do: @states

  @doc "Why an enrollment ends."
  @spec reasons() :: [String.t()]
  def reasons, do: @reasons

  @doc false
  def changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [
      :campaign_id,
      :person,
      :state,
      :reason,
      :entered_at,
      :cursor,
      :next_at,
      :last_sent_at,
      :ended_at
    ])
    |> validate_required([:campaign_id, :person, :state, :entered_at, :cursor])
    |> validate_length(:person, max: 255)
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:reason, @reasons)
    |> unique_constraint([:campaign_id, :person])
  end
end
