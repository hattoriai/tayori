defmodule Tayori.Campaigns.Schema do
  @moduledoc false
  # What the schemas of the campaigns share: a condition field checked by
  # Tayori.Conditions and kept normalized.

  import Ecto.Changeset

  alias Tayori.Conditions

  @doc false
  # Options: `:required` - nil is refused (else nil stays nil, "no
  # condition"); `:segment_id` - the segment the condition is of.
  def validate_condition(changeset, field, attributes, opts \\ []) do
    case fetch_field(changeset, field) do
      {_source, nil} ->
        if opts[:required], do: add_error(changeset, field, "can't be blank"), else: changeset

      {_source, condition} ->
        validate(changeset, field, condition, attributes, opts)
    end
  end

  defp validate(changeset, field, condition, attributes, opts) do
    case Conditions.validate(condition, attributes, Keyword.take(opts, [:segment_id])) do
      {:ok, normalized} -> put_change(changeset, field, normalized)
      {:error, messages} -> Enum.reduce(messages, changeset, &add_error(&2, field, &1))
    end
  end
end
