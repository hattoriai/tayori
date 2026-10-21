defmodule Tayori.Campaigns.Delivery do
  @moduledoc """
  A letter of a campaign to one person, once: a step of a campaign goes
  to a person at most one time.

    * `:status` - `"queued"`, `"sent"`, `"skipped"` (with its `:reason`,
      such as `"skip_if"` or `"no_email"`), `"failed"`, `"bounced"` or
      `"complained"`.
    * `:provider_id` - the id the mailer gave the email, which the
      provider's webhooks name.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(queued sent skipped failed bounced complained)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          campaign_id: Ecto.UUID.t() | nil,
          step_id: Ecto.UUID.t() | nil,
          person: String.t() | nil,
          email: String.t() | nil,
          locale: String.t() | nil,
          status: String.t(),
          reason: String.t() | nil,
          provider_id: String.t() | nil,
          sent_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tayori_deliveries" do
    belongs_to :campaign, Tayori.Campaigns.Campaign
    belongs_to :step, Tayori.Campaigns.Step
    field :person, :string
    field :email, :string
    field :locale, :string
    field :status, :string, default: "queued"
    field :reason, :string
    field :provider_id, :string
    field :sent_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The statuses of a delivery."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :campaign_id,
      :step_id,
      :person,
      :email,
      :locale,
      :status,
      :reason,
      :provider_id,
      :sent_at
    ])
    |> validate_required([:campaign_id, :person, :status])
    |> validate_length(:person, max: 255)
    |> validate_length(:email, max: 320)
    |> validate_length(:reason, max: 64)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:campaign_id, :step_id, :person])
  end
end
