defmodule Tayori.Entries do
  @moduledoc """
  Writes the news: what the admin does, for a script or a seed too.

      {:ok, entry} =
        Tayori.Entries.create(%{
          "categories" => ["New"],
          "translations" => [
            %{"locale" => "en", "title" => "Exports", "body" => Kotoba.Content.from_markdown("...")}
          ]
        })

      {:ok, entry} = Tayori.Entries.publish(entry)

  Every change is told on the PubSub (see `Tayori`), and the entry is
  announced once, when it is published (`Tayori.Notifier`).
  """

  import Ecto.Query

  alias Tayori.{Config, Entry, Translation}

  @doc """
  All the entries, for the admin: drafts and scheduled first, then the
  published, the newest first, with their translations.

  Options: `:search` - words of a title or a slug; `:status` - `:draft`,
  `:scheduled` or `:published`.
  """
  @spec list(keyword()) :: [Entry.t()]
  def list(opts \\ []) do
    config = Config.get()
    now = DateTime.utc_now()

    from(e in Entry,
      order_by: [
        asc:
          fragment(
            "CASE WHEN ? IS NULL THEN 0 WHEN ? > ? THEN 1 ELSE 2 END",
            e.published_at,
            e.published_at,
            ^now
          ),
        desc: coalesce(e.published_at, e.updated_at),
        desc: e.id
      ]
    )
    |> with_status(opts[:status], now)
    |> search(opts[:search])
    |> config.repo.all(prefix: config.prefix)
    |> config.repo.preload(:translations, prefix: config.prefix)
  end

  defp with_status(query, nil, _now), do: query
  defp with_status(query, :draft, _now), do: where(query, [e], is_nil(e.published_at))
  defp with_status(query, :scheduled, now), do: where(query, [e], e.published_at > ^now)
  defp with_status(query, :published, now), do: where(query, [e], e.published_at <= ^now)

  defp search(query, blank) when blank in [nil, ""], do: query

  defp search(query, words) do
    like = "%" <> String.replace(String.downcase(words), ~r/[\\%_]/, "\\\\\\0") <> "%"

    where(
      query,
      [e],
      like(fragment("lower(?)", e.slug), ^like) or
        e.id in subquery(
          from(t in Translation,
            where: like(fragment("lower(?)", t.title), ^like),
            select: t.entry_id
          )
        )
    )
  end

  @doc "An entry by its id, with its translations. Raises if there is none."
  @spec get!(Ecto.UUID.t()) :: Entry.t()
  def get!(id) do
    config = Config.get()

    Entry
    |> config.repo.get!(id, prefix: config.prefix)
    |> config.repo.preload(:translations, prefix: config.prefix)
  end

  @doc "A new entry, with an empty translation in the first language."
  @spec new() :: Entry.t()
  def new do
    config = Config.get()
    %Entry{translations: [%Translation{locale: Config.default_locale(config)}]}
  end

  @doc "A changeset of an entry, for a form."
  @spec change(Entry.t(), map()) :: Ecto.Changeset.t()
  def change(%Entry{} = entry, attrs \\ %{}) do
    Entry.changeset(entry, attrs, Config.get().locales)
  end

  @doc """
  Creates an entry. Options: `:author` - who writes it, a map such as
  `%{"id" => ..., "name" => ...}`.
  """
  @spec create(map(), keyword()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs, opts \\ []) do
    config = Config.get()

    %Entry{translations: []}
    |> change(attrs)
    |> Entry.put_author(opts[:author])
    |> config.repo.insert(prefix: config.prefix)
    |> changed()
  end

  @doc "Updates an entry: its fields, translations and publication time."
  @spec update(Entry.t(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def update(%Entry{} = entry, attrs) do
    config = Config.get()

    entry
    |> change(attrs)
    |> config.repo.update(prefix: config.prefix)
    |> changed()
  end

  @doc """
  Publishes an entry, now or at a time: a time in the future schedules
  it.
  """
  @spec publish(Entry.t(), DateTime.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def publish(%Entry{} = entry, at \\ DateTime.utc_now()) do
    put_published_at(entry, at)
  end

  @doc "Makes an entry a draft again. It will be announced again when it is published."
  @spec unpublish(Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def unpublish(%Entry{} = entry), do: put_published_at(entry, nil)

  defp put_published_at(entry, at) do
    config = Config.get()

    entry
    |> Ecto.Changeset.change(published_at: at, announced_at: nil)
    |> config.repo.update(prefix: config.prefix)
    |> changed()
  end

  @doc "Deletes an entry and its translations."
  @spec delete(Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Entry{} = entry) do
    config = Config.get()

    entry
    |> config.repo.delete(prefix: config.prefix)
    |> changed()
  end

  defp changed({:ok, entry}) do
    Tayori.broadcast({Tayori, :changed, entry.id})
    Tayori.Scheduler.wake()
    {:ok, entry}
  end

  defp changed(error), do: error
end
