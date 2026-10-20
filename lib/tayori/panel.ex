defmodule Tayori.Panel do
  @moduledoc false
  # The panel of the news as a state (Tayori.Live.State) and what a reader
  # does to it: open it, filter it, open an entry, go back, show more,
  # react, dismiss the announcement. Tayori.Live keeps the state in a
  # LiveView; Tayori.API makes it for each request of <tayori-news>. Both
  # render it with Tayori.Components: one panel, wherever it is shown.

  alias Tayori.{Announcements, Categories, Config, Messages, Reactions, Reader, Views}
  alias Tayori.Live.State

  @doc false
  # The closed panel of a reader (nil for a visitor), with its count of
  # unread entries and the announcement of the moment. Options: `:page`,
  # `:limit`, `:locale` (a visitor's language).
  @spec new(Reader.t() | nil, keyword()) :: State.t()
  def new(reader, opts \\ []) do
    config = Config.get()
    locale = (reader && reader.locale) || opts[:locale] || Config.default_locale(config)

    state = %State{
      reader: reader,
      unread: if(reader, do: Tayori.unread_count(reader), else: 0),
      page: opts[:page],
      locale: locale,
      locales: config.locales,
      messages: Messages.for_locale(locale),
      limit: Keyword.get(opts, :limit, 10),
      features: config.features,
      emoji: config.reactions
    }

    %{state | announcement: Announcements.current(reader_of(state))}
  end

  @doc false
  # The reader of the state, a visitor in its language when there is none.
  @spec reader_of(State.t()) :: Reader.t()
  def reader_of(%State{reader: nil, locale: locale}), do: Reader.visitor(locale)
  def reader_of(%State{reader: reader}), do: reader

  @doc false
  # Opens the panel on the list, and marks the news seen: what was new
  # until now keeps its mark while the panel is open.
  @spec open(State.t()) :: State.t()
  def open(%State{} = state) do
    seen_before = state.reader && Tayori.new_after(state.reader)
    if state.reader, do: Tayori.mark_seen(state.reader)

    %{state | open: true, unread: 0, seen_before: seen_before, entry: nil}
    |> Map.put(:categories, Categories.by_key())
    |> load()
  end

  @doc false
  @spec close(State.t()) :: State.t()
  def close(%State{} = state), do: %{state | open: false, entry: nil}

  @doc false
  # The first page of the list (or `limit` entries), with the pinned ones
  # beside the limit, and their reactions.
  @spec load(State.t(), pos_integer() | nil) :: State.t()
  def load(%State{} = state, limit \\ nil) do
    limit = limit || state.limit
    entries = Tayori.news(reader_of(state), limit: limit + 1, category: state.category)
    pinned = Enum.count(entries, & &1.pinned_at)

    %{
      state
      | entries: Enum.take(entries, limit + pinned),
        more: length(entries) > limit + pinned
    }
    |> reactions()
  end

  @doc false
  # The next page of the list, after the entries shown.
  @spec more(State.t()) :: State.t()
  def more(%State{} = state) do
    more =
      Tayori.news(reader_of(state),
        limit: state.limit + 1,
        before: state.entries |> Enum.reject(& &1.pinned_at) |> List.last(),
        category: state.category
      )

    %{
      state
      | entries: state.entries ++ Enum.take(more, state.limit),
        more: length(more) > state.limit
    }
    |> reactions()
  end

  @doc false
  # The list of a category, or of all (nil).
  @spec filter(State.t(), String.t() | nil) :: State.t()
  def filter(%State{} = state, category) do
    load(%{state | category: category, entry: nil})
  end

  @doc false
  # Opens an entry of the list, or the announcement, whole: a view in
  # `source` with the `:analytics` feature. Reading the announcement is
  # enough of an answer to it. `:error` for an entry the reader does not
  # have in front of them.
  @spec show(State.t(), String.t(), String.t()) :: {:ok, State.t()} | :error
  def show(%State{} = state, id, source) do
    case Enum.find(state.entries, &(&1.id == id)) || announcement(state, id) do
      nil ->
        :error

      entry ->
        if :analytics in state.features, do: Views.track(state.reader, entry.id, source)

        state =
          if announcement(state, id), do: read_announcement(state, entry), else: state

        # The reactions of the entry and of the list, for the way back.
        {:ok, reactions(%{state | open: true, entry: entry})}
    end
  end

  defp announcement(%State{announcement: %{id: id} = entry}, id), do: entry
  defp announcement(_state, _id), do: nil

  # The panel opens on the announcement, with the list to go back to.
  defp read_announcement(state, entry) do
    if state.reader, do: Announcements.dismiss(state.reader, entry.id)
    state = %{state | announcement: nil, categories: Categories.by_key()}
    if state.open, do: state, else: load(state)
  end

  @doc false
  @spec back(State.t()) :: State.t()
  def back(%State{} = state), do: %{state | entry: nil}

  @doc false
  # Turns a reaction of the reader on or off, to an entry they have in
  # front of them: the id is the client's.
  @spec react(State.t(), String.t(), String.t()) :: State.t()
  def react(%State{} = state, id, emoji) do
    if :reactions in state.features && state.reader && shown?(state, id) do
      _ = Reactions.toggle(state.reader, id, emoji)
      reactions(state)
    else
      state
    end
  end

  @doc false
  # Dismisses the announcement, for the reader on every device.
  @spec dismiss(State.t(), String.t()) :: State.t()
  def dismiss(%State{} = state, id) do
    if state.reader, do: Announcements.dismiss(state.reader, id)
    %{state | announcement: nil}
  end

  @doc false
  # The entries in front of the reader: the one open, and the list.
  @spec shown(State.t()) :: [Tayori.Entry.t()]
  def shown(%State{entry: nil, entries: entries}), do: entries
  def shown(%State{entry: entry, entries: entries}), do: [entry | entries]

  defp shown?(state, id), do: Enum.any?(shown(state), &(&1.id == id))

  @doc false
  # The counts and the reader's own reactions of the entries shown.
  @spec reactions(State.t()) :: State.t()
  def reactions(%State{} = state) do
    if :reactions in state.features do
      ids = state |> shown() |> Enum.map(& &1.id) |> Enum.uniq()
      %{state | reactions: Reactions.for_entries(reader_of(state), ids)}
    else
      state
    end
  end
end
