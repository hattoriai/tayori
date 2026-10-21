defmodule Tayori.Campaigns.Suppression do
  @moduledoc """
  An address the campaigns do not write to: for a `:purpose`
  (`"marketing"` or `"product"`), or for `"all"`. The `:reason` is
  `"unsubscribed"`, `"bounced"`, `"complained"` or `"manual"`. The
  address is kept lowercased, so that one address is one row for each
  purpose.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @purposes ~w(all marketing product)
  @reasons ~w(unsubscribed bounced complained manual)

  @type t :: %__MODULE__{
          email: String.t() | nil,
          purpose: String.t() | nil,
          reason: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key false
  schema "tayori_suppressions" do
    field :email, :string, primary_key: true
    field :purpose, :string, primary_key: true
    field :reason, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "What an address can be suppressed for."
  @spec purposes() :: [String.t()]
  def purposes, do: @purposes

  @doc "Why an address is suppressed."
  @spec reasons() :: [String.t()]
  def reasons, do: @reasons

  @doc false
  def changeset(suppression, attrs) do
    suppression
    |> cast(attrs, [:email, :purpose, :reason])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email, :purpose, :reason])
    |> validate_length(:email, max: 320)
    |> validate_format(:email, ~r/\A[^\s@]+@[^\s@]+\z/, message: "must be an address")
    |> validate_inclusion(:purpose, @purposes)
    |> validate_inclusion(:reason, @reasons)
  end
end
