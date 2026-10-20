defmodule Tayori.Digest do
  @moduledoc """
  An entry made of the inbox's changes (`Tayori.Inbox`): the changes
  waiting, for the public, grouped by category, the highlighted first.

      {:ok, entry} = Tayori.Digest.run()
      {:ok, entry} = Tayori.Digest.run(ids: ["0193…", "0194…"])

  The entry is a draft for the admin to read and publish, unless the
  `:digest` config says `publish: :publish`; the changes it takes are
  then `"drafted"`, with the entry's id. A change for the team only
  (`audience: "internal"`), or put aside, never goes into one.

  One change makes an entry of its own: its title and its body. Several
  make an entry titled with the day, with a section for each category.
  """

  alias Tayori.{Categories, Category, Config, Entries, Inbox, Messages}

  @doc """
  Makes an entry of the changes waiting. Options:

    * `:ids` - these changes only (still only the new, public ones).
    * `:since`, `:until` - the changes that happened in this time.
    * `:publish` - `:draft` or `:publish`, instead of the config's.
    * `:now` - the time of the digest (now).

  Returns `{:ok, entry}`, `{:error, :nothing}` when no change is
  waiting, or `{:error, changeset}`.
  """
  @spec run(keyword()) :: {:ok, Tayori.Entry.t()} | {:error, :nothing | Ecto.Changeset.t()}
  def run(opts \\ []) do
    config = Config.get()

    case Inbox.pending(Keyword.take(opts, [:ids, :since, :until])) do
      [] ->
        {:error, :nothing}

      changes ->
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
        publish = Keyword.get(opts, :publish, config.digest.publish)

        with {:ok, entry} <- Entries.create(attrs(changes, config, now)),
             {:ok, entry} <- maybe_publish(entry, publish, now) do
          Inbox.drafted(Enum.map(changes, & &1.id), entry.id)
          {:ok, entry}
        end
    end
  end

  defp maybe_publish(entry, :publish, now), do: Entries.publish(entry, now)
  defp maybe_publish(entry, _draft, _now), do: {:ok, entry}

  @doc false
  # The entry of the changes, in the first language.
  @spec attrs([Tayori.Change.t()], Config.t(), DateTime.t()) :: map()
  def attrs(changes, config, now) do
    locale = Config.default_locale(config)
    {title, summary, markdown} = text(changes, locale, config, now)

    %{
      categories: changes |> Enum.map(& &1.category) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      segments: segments(changes),
      translations: [
        %{
          locale: locale,
          title: title,
          summary: summary,
          body: Kotoba.Content.from_markdown(markdown)
        }
      ]
    }
  end

  defp text([change], _locale, _config, _now) do
    {change.title, nil, change.body || ""}
  end

  defp text(changes, locale, config, now) do
    categories = Categories.by_key()
    messages = Messages.for_locale(locale)

    sections =
      changes
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {key, _} -> position(categories, key) end)
      |> Enum.map_join("\n\n", fn {key, changes} ->
        heading(categories, key, locale, config) <> Enum.map_join(changes, "\n", &item/1)
      end)

    {Messages.date(messages, now), nil, sections}
  end

  defp heading(_categories, nil, _locale, _config), do: ""

  defp heading(categories, key, locale, config) do
    case categories[key] do
      %Category{} = category -> "## " <> Category.name(category, locale, config.locales) <> "\n\n"
      nil -> ""
    end
  end

  defp position(_categories, nil), do: {1, 0}

  defp position(categories, key) do
    case categories[key] do
      %Category{position: position} -> {0, position}
      nil -> {1, 0}
    end
  end

  defp item(change) do
    title = if change.highlight, do: "**#{change.title}**", else: change.title

    case change.body do
      body when is_binary(body) and body != "" ->
        "- #{title}: " <> (body |> String.replace(~r/\s*\n\s*/, " ") |> trim_title(change.title))

      _ ->
        "- #{title}"
    end
  end

  # A body that starts with its title says it once.
  defp trim_title(body, title) do
    if String.starts_with?(body, title),
      do: body |> String.replace_prefix(title, "") |> String.replace(~r/^[\s.:,;—–-]+/u, ""),
      else: body
  end

  # An entry is for every reader unless all its changes are for some.
  defp segments(changes) do
    if Enum.all?(changes, &(&1.segments != [])),
      do: changes |> Enum.flat_map(& &1.segments) |> Enum.uniq(),
      else: []
  end
end
