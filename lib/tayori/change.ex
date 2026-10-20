defmodule Tayori.Change do
  @moduledoc """
  A change in the inbox (`Tayori.Inbox`): one thing that shipped, as a
  source brought it, before it becomes an entry or part of one.

    * `:source` - where it came from: `"changelog"`, `"fragments"`,
      `"api"`, `"github"`, `"app"`, `"mcp"`, or a source of the app's own.
    * `:ref` - its name in its source (a file, a version and its text, a
      pull request): a change brought again with the same source and ref
      is the same change.
    * `:title` and `:body` - what changed, the body in Markdown.
    * `:kind` - the source's own word for it (`"added"`, `"fix"`,
      `"feature"`); `:category` - the key of a `Tayori.Category`, given or
      from the kind (the `:kinds` of the `:inbox` config).
    * `:audience` - `"public"`, or `"internal"`: a change for the team
      only, never put in an entry.
    * `:segments` - the readers it is for, as an entry's.
    * `:highlight` - worth leading with.
    * `:version`, `:url`, `:author` - where it shipped, a link to it (a
      pull request), who made it.
    * `:occurred_at` - when it happened (when it came, unless said).
    * `:state` - `"new"`; `"drafted"` once in an entry (`:entry_id`);
      `"hidden"` when the admin put it aside.
    * `:meta` - whatever else the source keeps.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          source: String.t() | nil,
          ref: String.t() | nil,
          title: String.t() | nil,
          body: String.t() | nil,
          kind: String.t() | nil,
          category: String.t() | nil,
          audience: String.t(),
          segments: [String.t()],
          highlight: boolean(),
          version: String.t() | nil,
          url: String.t() | nil,
          author: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          state: String.t(),
          entry_id: Ecto.UUID.t() | nil,
          meta: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @audiences ~w(public internal)
  @states ~w(new drafted hidden)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tayori_changes" do
    field :source, :string
    field :ref, :string
    field :title, :string
    field :body, :string
    field :kind, :string
    field :category, :string
    field :audience, :string, default: "public"
    field :segments, {:array, :string}, default: []
    field :highlight, :boolean, default: false
    field :version, :string
    field :url, :string
    field :author, :string
    field :occurred_at, :utc_datetime_usec
    field :state, :string, default: "new"
    field :entry_id, :binary_id
    field :meta, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The audiences of a change."
  @spec audiences() :: [String.t()]
  def audiences, do: @audiences

  @doc "The states of a change."
  @spec states() :: [String.t()]
  def states, do: @states

  @doc false
  # A change as a source brings it.
  def changeset(change, attrs) do
    change
    |> cast(attrs, [
      :source,
      :ref,
      :title,
      :body,
      :kind,
      :category,
      :audience,
      :segments,
      :highlight,
      :version,
      :url,
      :author,
      :occurred_at,
      :meta
    ])
    |> update_change(:title, &squish/1)
    |> update_change(:kind, &downcase/1)
    |> update_change(:audience, &downcase/1)
    |> update_change(:segments, &clean_list/1)
    |> validate_required([:source, :ref, :title])
    |> validate_length(:source, max: 32)
    |> validate_length(:ref, max: 255)
    |> validate_length(:title, max: 255)
    |> validate_length(:kind, max: 32)
    |> validate_length(:category, max: 64)
    |> validate_length(:version, max: 64)
    |> validate_length(:url, max: 2048)
    |> validate_length(:author, max: 255)
    |> validate_inclusion(:audience, @audiences)
    |> validate_url()
    |> unique_constraint([:source, :ref])
  end

  @doc false
  # What the admin changes of a change: where it goes, and for whom.
  def edit_changeset(change, attrs) do
    change
    |> cast(attrs, [:title, :body, :category, :audience, :segments, :highlight])
    |> update_change(:title, &squish/1)
    |> update_change(:segments, &clean_list/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 255)
    |> validate_inclusion(:audience, @audiences)
  end

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and host not in [nil, ""] ->
          []

        _ ->
          [url: "must be an http(s) address"]
      end
    end)
  end

  defp squish(nil), do: nil
  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp downcase(nil), do: nil
  defp downcase(text), do: text |> String.trim() |> String.downcase()

  defp clean_list(nil), do: []

  defp clean_list(list) when is_list(list),
    do: list |> Enum.map(&String.trim(to_string(&1))) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
end
