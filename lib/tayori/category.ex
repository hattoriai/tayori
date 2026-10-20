defmodule Tayori.Category do
  @moduledoc """
  A category of entries ("New", "Improved", "Fixed"): a key, its name in
  each language, a colour and its place in the list. Entries keep the keys
  of their categories.

  The colour is one of `colors/0`, a name the themes give a hue to
  (`--tayori-category-blue`, say), so that a category looks right in
  every theme, light and dark.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @colors ~w(gray red orange amber green teal blue purple pink)

  @type t :: %__MODULE__{
          key: String.t() | nil,
          names: %{optional(String.t()) => String.t()},
          color: String.t(),
          position: integer()
        }

  @primary_key {:key, :string, autogenerate: false}
  schema "tayori_categories" do
    field :names, :map, default: %{}
    field :color, :string, default: "gray"
    field :position, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The colours a category can have."
  @spec colors() :: [String.t()]
  def colors, do: @colors

  @doc """
  The name of a category in a language, else in the first of `locales`,
  else its key.
  """
  @spec name(t(), String.t() | nil, [String.t()]) :: String.t()
  def name(%__MODULE__{names: names, key: key}, locale, locales) do
    present(names[locale]) || present(names[List.first(locales)]) ||
      Enum.find_value(names, fn {_locale, name} -> present(name) end) || key
  end

  defp present(name) when is_binary(name) and name != "", do: name
  defp present(_name), do: nil

  @doc false
  def changeset(category, attrs, locales) do
    category
    |> cast(attrs, [:key, :names, :color, :position])
    |> update_change(:names, &clean_names(&1, locales))
    |> put_key(locales)
    |> validate_required([:key, :names, :color])
    |> validate_length(:key, max: 64)
    |> validate_format(:key, ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
      message: "use lowercase letters, digits and dashes"
    )
    |> validate_inclusion(:color, @colors)
    |> unsafe_validate_unique(:key, Tayori.Config.get().repo,
      prefix: Tayori.Config.get().prefix,
      message: "is the key of another category"
    )
    |> validate_change(:names, fn :names, names ->
      if Map.has_key?(names, List.first(locales)),
        do: [],
        else: [names: "needs the #{List.first(locales)} name"]
    end)
  end

  defp clean_names(names, locales) when is_map(names) do
    for {locale, name} <- names,
        locale in locales,
        is_binary(name),
        name = String.trim(name),
        name != "",
        into: %{},
        do: {locale, String.slice(name, 0, 60)}
  end

  defp clean_names(_names, _locales), do: %{}

  # A new category's key comes from its name in the first language.
  defp put_key(changeset, locales) do
    if changeset.data.key == nil and get_change(changeset, :key) in [nil, ""] do
      name = (get_field(changeset, :names) || %{})[List.first(locales)] || ""
      put_change(changeset, :key, Tayori.Entry.slugify(name))
    else
      changeset
    end
  end
end
