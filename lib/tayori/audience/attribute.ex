defmodule Tayori.Audience.Attribute do
  @moduledoc """
  A fact about a person that conditions may test: its key, its label in
  the admin, its type, and its expression, an Ecto `dynamic` on the
  `:person` binding of the audience's query. Made with
  `Tayori.Audience.attribute/5`.

  The types:

    * `:string`, `:integer`, `:boolean`;
    * `:datetime` (UTC) and `:date`;
    * `{:enum, [{value, label}]}` - one of a few strings, each with its
      label.
  """

  @type type ::
          :string | :integer | :boolean | :datetime | :date | {:enum, [{String.t(), String.t()}]}

  @type t :: %__MODULE__{
          key: String.t(),
          label: String.t(),
          type: type(),
          expr: Ecto.Query.dynamic_expr(),
          description: String.t() | nil
        }

  @enforce_keys [:key, :label, :type, :expr]
  defstruct [:key, :label, :type, :expr, :description]

  @doc false
  def types, do: [:string, :integer, :boolean, :datetime, :date, :enum]

  @doc false
  def type?({:enum, values}) when is_list(values) and values != [] do
    Enum.all?(values, &match?({value, label} when is_binary(value) and is_binary(label), &1))
  end

  def type?(type), do: type in [:string, :integer, :boolean, :datetime, :date]

  @doc "The name of an attribute's type: `:enum` for an enum."
  @spec type_name(t() | type()) :: atom()
  def type_name(%__MODULE__{type: type}), do: type_name(type)
  def type_name({:enum, _values}), do: :enum
  def type_name(type), do: type
end
