defmodule Tayori.Campaigns.Campaign do
  @moduledoc """
  A campaign: letters to the app's people. Two kinds:

    * `"sequence"` - a person enters on an event (`:trigger`), or by hand,
      then gets its steps' letters at their times from their entry, until
      the goal is reached, the steps end or `:max_days` pass. Its
      `:status` is `"draft"`, `"active"`, `"paused"` or `"archived"`.
    * `"broadcast"` - one letter to everyone in its audience, now or at
      `:send_at`. Its `:status` is `"draft"`, `"scheduled"`, `"sending"`,
      `"sent"` or `"archived"`.

  The rest:

    * `:purpose` - `"product"`, what the product needs to say, or
      `"marketing"`; a person unsubscribes from one or both.
    * `:trigger` - of a sequence: `%{"type" => "event", "event" => "signed_up"}`
      or `%{"type" => "manual"}`.
    * `:audience` - a condition (`Tayori.Conditions`): who may enter a
      sequence, or who gets a broadcast. Nil is everyone.
    * `:goal` - a condition: a person who matches it leaves the sequence,
      done. Nil for none.
    * `:min_gap_hours` - the hours at least between two letters of a
      sequence to one person (24).
    * `:max_days` - the days after their entry a person stays in a
      sequence, or nil.
    * `:from_name` and `:reply_to` - instead of those of the config.
    * `:author` - who made it, as the admin's resolver gave them.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tayori.Campaigns.{Schema, Step}

  @kinds ~w(sequence broadcast)
  @purposes ~w(product marketing)
  @statuses %{
    "sequence" => ~w(draft active paused archived),
    "broadcast" => ~w(draft scheduled sending sent archived)
  }

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          kind: String.t() | nil,
          purpose: String.t(),
          status: String.t(),
          trigger: map() | nil,
          audience: map() | nil,
          goal: map() | nil,
          min_gap_hours: non_neg_integer(),
          max_days: pos_integer() | nil,
          send_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          sent_at: DateTime.t() | nil,
          from_name: String.t() | nil,
          reply_to: String.t() | nil,
          author: map() | nil,
          steps: [Step.t()] | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tayori_campaigns" do
    field :name, :string
    field :kind, :string
    field :purpose, :string, default: "product"
    field :status, :string, default: "draft"
    field :trigger, :map
    field :audience, :map
    field :goal, :map
    field :min_gap_hours, :integer, default: 24
    field :max_days, :integer
    field :send_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :sent_at, :utc_datetime_usec
    field :from_name, :string
    field :reply_to, :string
    field :author, :map
    has_many :steps, Step, preload_order: [asc: :wait, asc: :position]
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The kinds of campaigns."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "Why a campaign writes."
  @spec purposes() :: [String.t()]
  def purposes, do: @purposes

  @doc "The statuses of a kind of campaign."
  @spec statuses(String.t()) :: [String.t()]
  def statuses(kind) when kind in @kinds, do: Map.fetch!(@statuses, kind)

  @doc false
  def changeset(campaign, attrs, attributes) do
    campaign
    |> cast(attrs, [
      :name,
      :kind,
      :purpose,
      :status,
      :trigger,
      :audience,
      :goal,
      :min_gap_hours,
      :max_days,
      :send_at,
      :from_name,
      :reply_to
    ])
    |> update_change(:name, &String.trim/1)
    |> update_change(:from_name, &blank_to_nil/1)
    |> update_change(:reply_to, &blank_to_nil/1)
    |> validate_required([:name, :kind, :purpose, :status, :min_gap_hours])
    |> validate_length(:name, max: 160)
    |> validate_length(:from_name, max: 160)
    |> validate_length(:reply_to, max: 320)
    |> validate_format(:reply_to, ~r/\A[^\s@]+@[^\s@]+\z/, message: "must be an address")
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:purpose, @purposes)
    |> validate_number(:min_gap_hours, greater_than_or_equal_to: 0)
    |> validate_number(:max_days, greater_than: 0)
    |> validate_status()
    |> validate_trigger()
    |> Schema.validate_condition(:audience, attributes)
    |> Schema.validate_condition(:goal, attributes)
  end

  defp validate_status(changeset) do
    with kind when kind in @kinds <- get_field(changeset, :kind),
         status when is_binary(status) <- get_field(changeset, :status),
         false <- status in statuses(kind) do
      add_error(changeset, :status, "is not a status of a #{kind}")
    else
      _ -> changeset
    end
  end

  # A sequence starts on an event or by hand; a broadcast has no trigger.
  defp validate_trigger(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :trigger)} do
      {"sequence", nil} ->
        put_change(changeset, :trigger, %{"type" => "manual"})

      {"sequence", trigger} when is_map(trigger) ->
        case trigger(trigger) do
          {:ok, trigger} -> put_change(changeset, :trigger, trigger)
          :error -> add_error(changeset, :trigger, "must be an event or manual")
        end

      {"sequence", _other} ->
        add_error(changeset, :trigger, "must be an event or manual")

      {"broadcast", nil} ->
        changeset

      {"broadcast", _trigger} ->
        add_error(changeset, :trigger, "is only for a sequence")

      _ ->
        changeset
    end
  end

  defp trigger(trigger) do
    case Map.new(trigger, fn {key, value} -> {to_string(key), value} end) do
      %{"type" => "manual"} ->
        {:ok, %{"type" => "manual"}}

      %{"type" => "event", "event" => event} when is_binary(event) ->
        event = String.trim(event)

        if event != "" and String.length(event) <= 64,
          do: {:ok, %{"type" => "event", "event" => event}},
          else: :error

      _ ->
        :error
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
