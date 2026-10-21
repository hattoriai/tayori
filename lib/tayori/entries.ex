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

  alias Kotoba.Nodes.Attachment
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

  @doc "The number of entries of each status, for the admin's tabs."
  @spec counts() :: %{
          all: integer(),
          draft: integer(),
          scheduled: integer(),
          published: integer()
        }
  def counts do
    config = Config.get()
    now = DateTime.utc_now()

    {draft, scheduled, published} =
      from(e in Entry,
        select:
          {sum(fragment("CASE WHEN ? IS NULL THEN 1 ELSE 0 END", e.published_at)),
           sum(fragment("CASE WHEN ? > ? THEN 1 ELSE 0 END", e.published_at, ^now)),
           sum(fragment("CASE WHEN ? <= ? THEN 1 ELSE 0 END", e.published_at, ^now))}
      )
      |> config.repo.one(prefix: config.prefix)

    [draft, scheduled, published] = Enum.map([draft, scheduled, published], &to_int/1)

    %{
      all: draft + scheduled + published,
      draft: draft,
      scheduled: scheduled,
      published: published
    }
  end

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = n), do: Decimal.to_integer(n)
  defp to_int(n) when is_integer(n), do: n

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
      fragment("lower(?) LIKE ? ESCAPE '\\'", e.slug, ^like) or
        e.id in subquery(
          from(t in Translation,
            where: fragment("lower(?) LIKE ? ESCAPE '\\'", t.title, ^like),
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

  @doc "An entry by its id, with its translations, or nil."
  @spec get(Ecto.UUID.t()) :: Entry.t() | nil
  def get(id) do
    config = Config.get()

    case config.repo.get(Entry, id, prefix: config.prefix) do
      nil -> nil
      entry -> config.repo.preload(entry, :translations, prefix: config.prefix)
    end
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

  A slug made from the title that another entry has takes a number:
  `exports-2`. A slug given is the entry's, or an error.
  """
  @spec create(map(), keyword()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs, opts \\ []) do
    config = Config.get()

    changeset =
      %Entry{translations: []}
      |> change(attrs)
      |> Entry.put_author(opts[:author])

    given? = (attrs[:slug] || attrs["slug"]) not in [nil, ""]

    write(config, fn ->
      insert(
        changeset,
        config,
        if(given?, do: nil, else: Ecto.Changeset.get_change(changeset, :slug)),
        2
      )
    end)
  end

  @max_slug_tries 50

  # In a savepoint: a slug taken rolls back this insert alone, and the
  # write's transaction goes on with the next slug (PostgreSQL aborts a
  # transaction at its first error otherwise).
  defp insert(changeset, config, base, n) do
    case config.repo.insert(changeset, prefix: config.prefix, mode: :savepoint) do
      {:error, failed} when is_binary(base) and n <= @max_slug_tries ->
        if slug_taken?(failed) do
          slug = String.slice(base, 0, 150) <> "-#{n}"
          changeset |> Ecto.Changeset.put_change(:slug, slug) |> insert(config, base, n + 1)
        else
          {:error, failed}
        end

      result ->
        result
    end
  end

  defp slug_taken?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_, meta}} ->
      field == :slug and meta[:constraint] == :unique
    end)
  end

  @doc "Updates an entry: its fields, translations and publication time."
  @spec update(Entry.t(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def update(%Entry{} = entry, attrs) do
    config = Config.get()

    write(config, fn -> entry |> change(attrs) |> config.repo.update(prefix: config.prefix) end)
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

    write(config, fn ->
      entry
      |> Ecto.Changeset.change(published_at: usec(at), announced_at: nil)
      |> config.repo.update(prefix: config.prefix)
    end)
  end

  # The times are kept to the microsecond; a time read from a form has
  # whole seconds.
  defp usec(nil), do: nil
  defp usec(%DateTime{microsecond: {value, _precision}} = at), do: %{at | microsecond: {value, 6}}

  @doc "Pins an entry: pinned entries come first, the last pinned first."
  @spec pin(Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def pin(%Entry{} = entry), do: put(entry, pinned_at: usec(DateTime.utc_now()))

  @doc "Unpins an entry."
  @spec unpin(Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def unpin(%Entry{} = entry), do: put(entry, pinned_at: nil)

  @doc """
  Puts a cover on an entry, from a stored image: a
  `Kotoba.Nodes.Attachment` (as `Kotoba.Attachments.store/2` or an upload
  of the admin makes it), with its alternative text. Only an image can be
  a cover.
  """
  @spec put_cover(Entry.t(), Attachment.t(), String.t() | nil) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t() | :not_an_image}
  def put_cover(%Entry{} = entry, %Attachment{} = image, alt \\ nil) do
    if Attachment.image?(image) do
      put(entry,
        cover: %{
          "url" => image.url,
          "key" => image.key,
          "width" => image.width,
          "height" => image.height,
          "alt" => alt || ""
        }
      )
    else
      {:error, :not_an_image}
    end
  end

  @doc false
  # The admin's cover: a map it made from an image it stored.
  def put_cover_map(%Entry{} = entry, nil), do: remove_cover(entry)

  def put_cover_map(%Entry{} = entry, %{"url" => url} = cover) when is_binary(url) do
    put(entry, cover: Map.take(cover, ["url", "key", "width", "height", "alt"]))
  end

  @doc "Changes the alternative text of an entry's cover."
  @spec put_cover_alt(Entry.t(), String.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def put_cover_alt(%Entry{cover: %{} = cover} = entry, alt) when is_binary(alt),
    do: put(entry, cover: Map.put(cover, "alt", String.slice(String.trim(alt), 0, 300)))

  @doc """
  Takes the cover off an entry. The image stays in the storage: delete it
  with the storage adapter (`Kotoba.Storage`) if nothing else uses it.
  """
  @spec remove_cover(Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def remove_cover(%Entry{} = entry), do: put(entry, cover: nil)

  defp put(entry, changes) do
    config = Config.get()

    write(config, fn ->
      entry |> Ecto.Changeset.change(changes) |> config.repo.update(prefix: config.prefix)
    end)
  end

  @doc "Deletes an entry and its translations."
  @spec delete(Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Entry{} = entry) do
    config = Config.get()

    write(config, fn -> config.repo.delete(entry, prefix: config.prefix) end)
  end

  # A write of an entry, and with Oban its announcement's job, in one
  # transaction: both are kept, or neither. Then the pages hear of it, and
  # without Oban the scheduler looks again.
  defp write(config, fun) do
    config.repo.transaction(fn ->
      case fun.() do
        {:ok, entry} -> tap(entry, &Tayori.Jobs.entry_written(config, &1))
        {:error, changeset} -> config.repo.rollback(changeset)
      end
    end)
    |> changed(config)
  end

  defp changed({:ok, entry}, config) do
    Tayori.broadcast({Tayori, :changed, entry.id})
    if config.oban == nil, do: Tayori.Scheduler.wake()
    {:ok, entry}
  end

  defp changed(error, _config), do: error
end
