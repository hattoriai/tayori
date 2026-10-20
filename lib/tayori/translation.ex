defmodule Tayori.Translation do
  @moduledoc """
  An entry in one language: its title, an optional summary (what the
  panel and the emails show), and its body, a `Kotoba.Content`.

    * `:text` - the plain text of the body, kept for search.
    * `:seo_title` and `:seo_description` - what search engines and
      shared links show, when not the title and the summary.
    * `:cta_label` and `:cta_url` - the button of its announcement in the
      app ("Try it", a path or a URL).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          entry_id: Ecto.UUID.t() | nil,
          locale: String.t() | nil,
          title: String.t() | nil,
          summary: String.t() | nil,
          body: Kotoba.Content.t() | nil,
          text: String.t() | nil,
          seo_title: String.t() | nil,
          seo_description: String.t() | nil,
          cta_label: String.t() | nil,
          cta_url: String.t() | nil
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
    field :text, :string
    field :seo_title, :string
    field :seo_description, :string
    field :cta_label, :string
    field :cta_url, :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The Kotoba features of an entry's body."
  @spec features() :: [atom()]
  def features, do: @features

  @doc false
  def changeset(translation, attrs, locales) do
    translation
    |> cast(attrs, [
      :locale,
      :title,
      :summary,
      :body,
      :seo_title,
      :seo_description,
      :cta_label,
      :cta_url
    ])
    |> update_change(:title, &String.trim/1)
    |> update_change(:summary, &blank_to_nil/1)
    |> update_change(:seo_title, &blank_to_nil/1)
    |> update_change(:seo_description, &blank_to_nil/1)
    |> update_change(:cta_label, &blank_to_nil/1)
    |> update_change(:cta_url, &blank_to_nil/1)
    |> validate_required([:locale, :title])
    |> validate_length(:title, max: 255)
    |> validate_length(:summary, max: 500)
    |> validate_length(:seo_title, max: 255)
    |> validate_length(:seo_description, max: 500)
    |> validate_length(:cta_label, max: 80)
    |> validate_length(:cta_url, max: 2048)
    |> validate_change(:cta_url, &safe_url/2)
    |> put_text()
    |> validate_inclusion(:locale, locales)
    |> Kotoba.Content.validate_features(:body, @features)
  end

  # The plain text of the body, for search.
  defp put_text(changeset) do
    case get_field(changeset, :body) do
      %Kotoba.Content{text: text} -> put_change(changeset, :text, text)
      _ -> changeset
    end
  end

  # A path of the app or an http(s) URL: the button of an announcement
  # never runs a script.
  defp safe_url(field, url) do
    if (String.starts_with?(url, "/") and not String.starts_with?(url, "//")) or
         match?(
           %URI{scheme: scheme, host: host}
           when scheme in ["http", "https"] and host not in [nil, ""],
           URI.parse(url)
         ),
       do: [],
       else: [{field, "must be a path of the app, or an http or https address"}]
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
