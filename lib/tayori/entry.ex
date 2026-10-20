defmodule Tayori.Entry do
  @moduledoc """
  An entry of the news: one thing the app has to say, in one or more
  languages (`Tayori.Translation`).

    * `:slug` - its address on the public page, from the title of its
      first language unless the admin gives one.
    * `:categories` - free labels ("New", "Improved", "Fixed"), shown on it.
    * `:segments` - the readers it is for: an entry with no segments is
      for everyone, and is the only kind on the public page; an entry with
      segments is for the readers in at least one of them (see
      `Tayori.Reader`).
    * `:published_at` - nil while it is a draft; a time in the future
      while it is scheduled.
    * `:author` - who wrote it, as the admin's resolver gave them
      (`%{"id" => ..., "name" => ...}`).

  `:translation` is not stored: the functions that read entries for a
  reader set it to the translation in the reader's language, or in the
  first language when the entry has none in theirs.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tayori.Translation

  @type status :: :draft | :scheduled | :published

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          slug: String.t() | nil,
          categories: [String.t()],
          segments: [String.t()],
          published_at: DateTime.t() | nil,
          announced_at: DateTime.t() | nil,
          author: map() | nil,
          translations: [Translation.t()] | Ecto.Association.NotLoaded.t(),
          translation: Translation.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tayori_entries" do
    field :slug, :string
    field :categories, {:array, :string}, default: []
    field :segments, {:array, :string}, default: []
    field :published_at, :utc_datetime_usec
    field :announced_at, :utc_datetime_usec
    field :author, :map
    field :translation, :any, virtual: true
    has_many :translations, Translation, on_replace: :delete, preload_order: [asc: :locale]
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The status of an entry at a time (now by default).

  ## Examples

      iex> Tayori.Entry.status(%Tayori.Entry{published_at: nil})
      :draft

      iex> Tayori.Entry.status(%Tayori.Entry{published_at: ~U[2000-01-01 00:00:00Z]})
      :published

  """
  @spec status(t(), DateTime.t()) :: status()
  def status(entry, now \\ DateTime.utc_now())
  def status(%__MODULE__{published_at: nil}, _now), do: :draft

  def status(%__MODULE__{published_at: at}, now) do
    if DateTime.compare(at, now) == :gt, do: :scheduled, else: :published
  end

  @doc """
  The translation of an entry in a language, else in the first of
  `locales`, else the first it has. Needs the translations preloaded.
  """
  @spec translation(t(), String.t() | nil, [String.t()]) :: Translation.t() | nil
  def translation(%__MODULE__{translations: translations}, locale, locales) do
    Enum.find(translations, &(&1.locale == locale)) ||
      Enum.find(translations, &(&1.locale == List.first(locales))) ||
      List.first(translations)
  end

  @doc false
  def changeset(entry, attrs, locales) do
    entry
    |> cast(attrs, [:slug, :categories, :segments, :published_at])
    |> update_change(:categories, &clean_list/1)
    |> update_change(:segments, &clean_list/1)
    |> cast_assoc(:translations,
      with: &Translation.changeset(&1, &2, locales),
      sort_param: :translations_sort,
      drop_param: :translations_drop
    )
    |> put_slug(locales)
    |> validate_required([:slug])
    |> validate_length(:slug, max: 160)
    |> validate_format(:slug, ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
      message: "use lowercase letters, digits and dashes"
    )
    |> validate_first_language(locales)
    |> unique_constraint(:slug)
  end

  @doc false
  def put_author(changeset, nil), do: changeset
  def put_author(changeset, author), do: put_change(changeset, :author, author)

  # A slug left empty comes from the title of the first language.
  defp put_slug(changeset, locales) do
    case get_field(changeset, :slug) do
      blank when blank in [nil, ""] ->
        title =
          changeset
          |> get_assoc(:translations, :struct)
          |> Enum.find(&(&1.locale == List.first(locales)))
          |> case do
            %Translation{title: title} when is_binary(title) -> title
            _ -> ""
          end

        put_change(changeset, :slug, slugify(title))

      _slug ->
        changeset
    end
  end

  defp validate_first_language(changeset, [first | _]) do
    translations = get_assoc(changeset, :translations, :struct)

    if Enum.any?(translations, &(&1.locale == first)) do
      changeset
    else
      add_error(changeset, :translations, "needs the #{first} version")
    end
  end

  @doc """
  A slug from a title: lowercase ASCII letters and digits, joined by
  dashes, with the accents taken off.

  ## Examples

      iex> Tayori.Entry.slugify("Ação rápida: exports in 2 clicks!")
      "acao-rapida-exports-in-2-clicks"

  """
  @spec slugify(String.t()) :: String.t()
  def slugify(title) do
    title
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 80)
    |> String.trim_trailing("-")
  end

  defp clean_list(values) do
    values
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
