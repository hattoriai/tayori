defmodule Tayori do
  @moduledoc """
  Tayori (便り) is product news for Phoenix: what the app has to say to
  its people, written in an admin the app mounts, and read in the app, on
  a public page, in feeds and in emails.

  Add Tayori to the app's supervision tree, after the repo and the
  PubSub (`Tayori.Config` has the options):

      {Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, secret_key_base: secret}

  The functions of this module read the news for a `Tayori.Reader`, built
  by the app from its own user: `news/2`, `entry/3`, `unread_count/2`,
  `mark_seen/2`. `Tayori.Entries` writes them; the admin
  (`Tayori.Router.tayori_admin/2`) is a page over it.

  Start with the [Quickstart](quickstart.md).

  ## Live

  `subscribe/0` subscribes the caller to the news on the app's PubSub. It
  receives:

    * `{Tayori, :published, id}` - an entry was published, at once or at
      its scheduled time;
    * `{Tayori, :changed, id}` - an entry was changed, unpublished or
      deleted.

  `subscribe/1` subscribes to a reader's own topic, which receives
  `{Tayori, :seen, reader_id}` when they see the news in another tab or
  on another device.
  """

  use Supervisor

  import Ecto.Query

  alias Tayori.{Config, Entry, Query, Reader}

  @external_resource "mix.exs"
  @version Mix.Project.config()[:version]

  @topic "tayori"

  @doc "Starts Tayori with the options of `Tayori.Config`."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl Supervisor
  def init(opts) do
    config = Config.new(opts)
    Config.put(config)

    children = [
      {Task.Supervisor, name: Tayori.TaskSupervisor},
      {Tayori.Scheduler, config}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  The news a reader sees, the newest first, each entry with its
  translation in the reader's language.

  Options:

    * `:limit` - how many entries (20).
    * `:before` - an entry: the entries published before it, for the next
      page.
    * `:now` - the time to read the news at (now).
  """
  @spec news(Reader.t(), keyword()) :: [Entry.t()]
  def news(%Reader{} = reader, opts \\ []) do
    config = Config.get()
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    config
    |> Query.visible(reader, now)
    |> before(opts[:before])
    |> Query.newest_first()
    |> limit(^Keyword.get(opts, :limit, 20))
    |> config.repo.all(prefix: config.prefix)
    |> with_translations(config, reader)
  end

  defp before(query, nil), do: query

  defp before(query, %Entry{published_at: at, id: id}) do
    where(query, [e], e.published_at < ^at or (e.published_at == ^at and e.id < ^id))
  end

  @doc """
  An entry of the news by its slug, if the reader sees it.
  """
  @spec entry(Reader.t(), String.t(), keyword()) :: Entry.t() | nil
  def entry(%Reader{} = reader, slug, opts \\ []) when is_binary(slug) do
    config = Config.get()
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    config
    |> Query.visible(reader, now)
    |> where([e], e.slug == ^slug)
    |> config.repo.all(prefix: config.prefix)
    |> with_translations(config, reader)
    |> List.first()
  end

  @doc """
  How many entries the reader has not seen: those published since they
  last saw the news (`mark_seen/2`), or since `reader.since`. Zero for a
  visitor.

  Options: `:now` (now), `:max` - stop counting there (99), so that the
  count is one cheap query.
  """
  @spec unread_count(Reader.t(), keyword()) :: non_neg_integer()
  def unread_count(reader, opts \\ [])
  def unread_count(%Reader{id: nil}, _opts), do: 0

  def unread_count(%Reader{} = reader, opts) do
    config = Config.get()
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    max = Keyword.get(opts, :max, 99)

    since = latest(seen_at(config, reader.id), reader.since)

    ids =
      config
      |> Query.visible(reader, now)
      |> after_time(since)
      |> select([e], e.id)
      |> limit(^max)

    config.repo.aggregate(subquery(ids), :count, prefix: config.prefix)
  end

  defp after_time(query, nil), do: query
  defp after_time(query, since), do: where(query, [e], e.published_at > ^since)

  defp latest(nil, b), do: b
  defp latest(a, nil), do: a
  defp latest(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  @doc """
  The time after which an entry is new to the reader: when they last saw
  the news, else `reader.since`, else the beginning of time (everything is
  new to a reader who never looked). Nil for a visitor: nothing is new.
  """
  @spec new_after(Reader.t()) :: DateTime.t() | nil
  def new_after(%Reader{id: nil}), do: nil

  def new_after(%Reader{} = reader) do
    latest(seen_at(reader), reader.since) || ~U[1970-01-01 00:00:00Z]
  end

  @doc """
  When the reader last saw the news, or nil.
  """
  @spec seen_at(Reader.t()) :: DateTime.t() | nil
  def seen_at(%Reader{id: nil}), do: nil
  def seen_at(%Reader{id: id}), do: seen_at(Config.get(), id)

  defp seen_at(config, id) do
    config.repo.one(
      from(r in "tayori_reads", where: r.reader == ^id, select: r.seen_at),
      prefix: config.prefix
    )
    |> case do
      nil -> nil
      %DateTime{} = at -> at
      %NaiveDateTime{} = at -> DateTime.from_naive!(at, "Etc/UTC")
      at when is_binary(at) -> parse_time(at)
    end
  end

  defp parse_time(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      {:error, _} -> text |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
    end
  end

  @doc """
  Marks the news as seen by the reader, at a time (now): what was
  published until then is no longer unread. Tells the reader's other tabs
  (`subscribe/1`). Does nothing for a visitor.
  """
  @spec mark_seen(Reader.t(), DateTime.t()) :: :ok
  def mark_seen(reader, at \\ DateTime.utc_now())
  def mark_seen(%Reader{id: nil}, _at), do: :ok

  def mark_seen(%Reader{id: id}, %DateTime{} = at) do
    config = Config.get()

    config.repo.insert_all(
      "tayori_reads",
      [%{reader: id, seen_at: at}],
      on_conflict: [set: [seen_at: at]],
      conflict_target: [:reader],
      prefix: config.prefix
    )

    Phoenix.PubSub.broadcast(config.pubsub, reader_topic(id), {Tayori, :seen, id})
    :ok
  end

  @doc "Subscribes the caller to the news (see the module doc)."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Config.get().pubsub, @topic)

  @doc "Subscribes the caller to a reader's own topic (see the module doc)."
  @spec subscribe(Reader.t()) :: :ok | {:error, term()}
  def subscribe(%Reader{id: nil}), do: :ok

  def subscribe(%Reader{id: id}),
    do: Phoenix.PubSub.subscribe(Config.get().pubsub, reader_topic(id))

  @doc false
  def broadcast(message), do: Phoenix.PubSub.broadcast(Config.get().pubsub, @topic, message)

  defp reader_topic(id), do: @topic <> ":reader:" <> id

  @doc false
  def with_translations(entries, config, reader) do
    entries
    |> config.repo.preload(:translations, prefix: config.prefix)
    |> Enum.map(&%{&1 | translation: Entry.translation(&1, reader.locale, config.locales)})
  end

  @doc """
  Returns the current Tayori version.

  ## Examples

      iex> Tayori.version()
      "#{@version}"

  """
  @spec version() :: String.t()
  def version, do: @version
end
