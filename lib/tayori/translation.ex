defmodule Tayori.Translation do
  @moduledoc """
  An entry in one language: its title, an optional summary (what the
  panel and the emails show), and its body, a `Kotoba.Content`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          entry_id: Ecto.UUID.t() | nil,
          locale: String.t() | nil,
          title: String.t() | nil,
          summary: String.t() | nil,
          body: Kotoba.Content.t() | nil
        }

  # What the body of an entry may hold: all of Kotoba but mentions, which
  # name people of the admin's app to readers who cannot follow them.
  @features ~w(bold italic underline strikethrough highlight inline_code links headings
               quotes lists check_lists code_blocks horizontal_rules tables attachments
               images footnotes)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tayori_translations" do
    belongs_to :entry, Tayori.Entry
    field :locale, :string
    field :title, :string
    field :summary, :string
    field :body, Kotoba.Content, default: Kotoba.Content.empty()
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The Kotoba features of an entry's body."
  @spec features() :: [atom()]
  def features, do: @features

  @doc false
  def changeset(translation, attrs, locales) do
    translation
    |> cast(attrs, [:locale, :title, :summary, :body])
    |> update_change(:title, &String.trim/1)
    |> update_change(:summary, &blank_to_nil/1)
    |> validate_required([:locale, :title])
    |> validate_length(:title, max: 255)
    |> validate_length(:summary, max: 500)
    |> validate_inclusion(:locale, locales)
    |> Kotoba.Content.validate_features(:body, @features)
  end

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
