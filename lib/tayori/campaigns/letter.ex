defmodule Tayori.Campaigns.Letter do
  @moduledoc """
  A step's letter in one language: its subject, a preheader (the line a
  mail client shows after the subject), its body, a `Kotoba.Content`,
  and an optional button.

    * `:text` - the plain text of the body, for the text part.
    * `:cta_label` and `:cta_url` - the button ("Open your dashboard", an
      http(s) URL).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          step_id: Ecto.UUID.t() | nil,
          locale: String.t() | nil,
          subject: String.t() | nil,
          preheader: String.t() | nil,
          body: Kotoba.Content.t() | nil,
          text: String.t() | nil,
          cta_label: String.t() | nil,
          cta_url: String.t() | nil
        }

  # What a letter may hold: what a mail client shows well.
  @features ~w(bold italic underline strikethrough highlight inline_code links headings
               quotes lists horizontal_rules images)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tayori_letters" do
    belongs_to :step, Tayori.Campaigns.Step
    field :locale, :string
    field :subject, :string
    field :preheader, :string
    field :body, Kotoba.Content, default: Kotoba.Content.empty()
    field :text, :string
    field :cta_label, :string
    field :cta_url, :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The Kotoba features of a letter's body."
  @spec features() :: [atom()]
  def features, do: @features

  @doc false
  def changeset(letter, attrs, locales) do
    letter
    |> cast(attrs, [:locale, :subject, :preheader, :body, :cta_label, :cta_url])
    |> update_change(:subject, &trim/1)
    |> update_change(:preheader, &blank_to_nil/1)
    |> update_change(:cta_label, &blank_to_nil/1)
    |> update_change(:cta_url, &blank_to_nil/1)
    |> validate_required([:locale, :subject])
    |> validate_inclusion(:locale, locales)
    |> validate_length(:subject, max: 255)
    |> validate_length(:preheader, max: 255)
    |> validate_length(:cta_label, max: 80)
    |> validate_length(:cta_url, max: 2048)
    |> validate_change(:cta_url, &http_url/2)
    |> put_text()
    |> Kotoba.Content.validate_features(:body, @features)
    |> unique_constraint([:step_id, :locale], message: "has a letter in this language")
  end

  # The plain text of the body, for the text part of the email.
  defp put_text(changeset) do
    case get_field(changeset, :body) do
      %Kotoba.Content{text: text} -> put_change(changeset, :text, text)
      _ -> changeset
    end
  end

  # A letter is read outside the app: its button goes to a whole address.
  defp http_url(field, url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        []

      _ ->
        if String.contains?(url, "{{"),
          do: [],
          else: [{field, "must be an http or https address"}]
    end
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
