defmodule Tayori.Live do
  @moduledoc """
  The news in the app's LiveViews: an `on_mount` hook that gives each
  LiveView of a `live_session` the `@tayori` assign, for the components of
  `Tayori.Components`.

      live_session :app,
        on_mount: [
          {MyAppWeb.UserAuth, :ensure_authenticated},
          {Tayori.Live, resolver: MyAppWeb.TayoriResolver, page: "/changelog"}
        ] do
        ...
      end

  Put it after the app's own hooks: the resolver reads the reader from
  the socket's assigns (`c:Tayori.Resolver.resolve_reader/1`).

  Options:

    * `:resolver` - the app's `Tayori.Resolver` (required). A module alone,
      `{Tayori.Live, MyAppWeb.TayoriResolver}`, is the resolver.
    * `:page` - the path of the public page (`Tayori.Router.tayori_page/2`),
      for the panel's link to all the news.
    * `:limit` - the entries of the panel, and of each "Show more" (10).

  `@tayori` holds the reader, the number of entries they have not seen
  (`@tayori.unread`), and, once the panel is open, its entries. It stays
  live: an entry published, scheduled or changed in the admin reaches
  every open page as it happens, and seeing the news in one tab clears
  the count in the others.

  The events `tayori:open`, `tayori:close` and `tayori:more` open the
  panel (and mark the news as seen), close it, and load more; the
  components send them, and a LiveView's own button can too
  (`phx-click="tayori:open"`). The hook handles them, and the messages of
  the PubSub, before the LiveView sees them.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias Tayori.{Reader, Resolver}

  defmodule State do
    @moduledoc """
    The `@tayori` assign:

      * `:reader` - nil for a visitor; `:unread` - its count of unread
        entries; `:seen_before` - the time the reader had seen the news
        until, for the "New" mark.
      * `:open` - whether the panel is open; `:entries` - its entries;
        `:more` - whether there are more; `:entry` - the entry open in the
        panel, or nil for the list; `:category` - the key of the category
        the list shows, or nil for all.
      * `:categories` - the categories by key; `:reactions` - the counts
        and the reader's own reactions of the entries shown
        (`{counts, mine}`, see `Tayori.Reactions.for_entries/2`).
      * `:announcement` - the entry announced to the reader now, or nil.
      * `:features` - the extras of the app (`Tayori.Config`);
        `:emoji` - the emoji readers react with.
      * `:page` - the public page's path; `:locale` and its `:messages`.
    """

    @type t :: %__MODULE__{
            reader: Tayori.Reader.t() | nil,
            unread: non_neg_integer(),
            open: boolean(),
            entries: [Tayori.Entry.t()],
            entry: Tayori.Entry.t() | nil,
            category: String.t() | nil,
            categories: %{String.t() => Tayori.Category.t()},
            reactions: {map(), map()},
            announcement: Tayori.Entry.t() | nil,
            features: [atom()],
            emoji: [String.t()],
            more: boolean(),
            seen_before: DateTime.t() | nil,
            page: String.t() | nil,
            locale: String.t(),
            locales: [String.t()],
            messages: map(),
            limit: pos_integer()
          }

    defstruct reader: nil,
              unread: 0,
              open: false,
              entries: [],
              entry: nil,
              category: nil,
              categories: %{},
              reactions: {%{}, %{}},
              announcement: nil,
              features: [],
              emoji: [],
              more: false,
              seen_before: nil,
              page: nil,
              locale: "en",
              locales: ["en"],
              messages: %{},
              limit: 10
  end

  @doc false
  def on_mount(resolver, params, session, socket) when is_atom(resolver) do
    on_mount([resolver: resolver], params, session, socket)
  end

  def on_mount(opts, _params, _session, socket) when is_list(opts) do
    resolver = Keyword.fetch!(opts, :resolver)
    reader = Resolver.reader(resolver, socket)
    config = Tayori.Config.get()
    locale = (reader && reader.locale) || Tayori.Config.default_locale(config)

    state = %State{
      reader: reader,
      unread: if(reader, do: Tayori.unread_count(reader), else: 0),
      page: opts[:page],
      locale: locale,
      locales: config.locales,
      messages: Tayori.Messages.for_locale(locale),
      limit: Keyword.get(opts, :limit, 10),
      features: config.features,
      emoji: config.reactions
    }

    socket =
      if connected?(socket) do
        Tayori.subscribe()
        if reader, do: Tayori.subscribe(reader)

        socket
        |> attach_hook(:tayori_events, :handle_event, &handle_event/3)
        |> attach_hook(:tayori_info, :handle_info, &handle_info/2)
      else
        socket
      end

    state = %{state | announcement: Tayori.Announcements.current(reader_of(state))}
    {:cont, assign(socket, :tayori, state)}
  end

  defp reader_of(state), do: state.reader || Reader.visitor(state.locale)

  defp handle_event("tayori:open", _params, socket) do
    state = socket.assigns.tayori
    seen_before = state.reader && Tayori.new_after(state.reader)

    if state.reader, do: Tayori.mark_seen(state.reader)

    state =
      %{state | open: true, unread: 0, seen_before: seen_before, entry: nil}
      |> Map.put(:categories, Tayori.Categories.by_key())
      |> load()

    track(state, state.entries)
    {:halt, put_state(socket, state)}
  end

  defp handle_event("tayori:close", _params, socket) do
    {:halt, put_state(socket, %{socket.assigns.tayori | open: false, entry: nil})}
  end

  defp handle_event("tayori:more", _params, socket) do
    state = socket.assigns.tayori

    more =
      Tayori.news(reader_of(state),
        limit: state.limit + 1,
        before: state.entries |> Enum.reject(& &1.pinned_at) |> List.last(),
        category: state.category
      )

    entries = state.entries ++ Enum.take(more, state.limit)

    {:halt,
     put_state(
       socket,
       %{state | entries: entries, more: length(more) > state.limit} |> reactions()
     )}
  end

  defp handle_event("tayori:filter", params, socket) do
    category = blank(params["category"])
    state = load(%{socket.assigns.tayori | category: category, entry: nil})
    {:halt, put_state(socket, state)}
  end

  defp handle_event("tayori:show", %{"id" => id}, socket) do
    state = socket.assigns.tayori

    case Enum.find(state.entries, &(&1.id == id)) ||
           (state.announcement && state.announcement.id == id && state.announcement) do
      nil ->
        {:halt, socket}

      entry ->
        track(state, [entry])

        # Reading the announcement is enough of an answer to it.
        state =
          if state.announcement && state.announcement.id == entry.id do
            if state.reader, do: Tayori.Announcements.dismiss(state.reader, entry.id)
            state = %{state | announcement: nil, categories: Tayori.Categories.by_key()}
            # The panel opens on it, with the list to go back to.
            if state.open, do: state, else: load(state)
          else
            state
          end

        # The reactions of the entry and of the list, for the way back.
        state = %{state | open: true, entry: entry}
        {:halt, put_state(socket, reactions(state))}
    end
  end

  defp handle_event("tayori:back", _params, socket) do
    {:halt, put_state(socket, %{socket.assigns.tayori | entry: nil})}
  end

  defp handle_event("tayori:react", %{"id" => id, "emoji" => emoji}, socket) do
    state = socket.assigns.tayori

    if :reactions in state.features and state.reader do
      _ = Tayori.Reactions.toggle(state.reader, id, emoji)
      {:halt, put_state(socket, reactions(state))}
    else
      {:halt, socket}
    end
  end

  defp handle_event("tayori:dismiss", %{"id" => id}, socket) do
    state = socket.assigns.tayori
    if state.reader, do: Tayori.Announcements.dismiss(state.reader, id)
    {:halt, put_state(socket, %{state | announcement: nil})}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info({Tayori, :seen, _id}, socket) do
    {:halt, put_state(socket, %{socket.assigns.tayori | unread: 0})}
  end

  defp handle_info({Tayori, :dismissed, id}, socket) do
    state = socket.assigns.tayori

    state =
      if state.announcement && state.announcement.id == id,
        do: %{state | announcement: nil},
        else: state

    {:halt, put_state(socket, state)}
  end

  defp handle_info({Tayori, :reacted, id}, socket) do
    state = socket.assigns.tayori

    if state.open and Enum.any?(shown(state), &(&1.id == id)),
      do: {:halt, put_state(socket, reactions(state))},
      else: {:halt, socket}
  end

  defp handle_info({Tayori, :categories, _key}, socket) do
    state = socket.assigns.tayori

    if state.open,
      do: {:halt, put_state(socket, %{state | categories: Tayori.Categories.by_key()})},
      else: {:halt, socket}
  end

  defp handle_info({Tayori, event, _id}, socket) when event in [:published, :changed] do
    state = socket.assigns.tayori

    state =
      cond do
        state.open ->
          # The panel shows the news as it is: what is published while it
          # is open is seen.
          if state.reader, do: Tayori.mark_seen(state.reader)
          state = load(state, max(length(state.entries), state.limit))

          entry =
            state.entry &&
              Enum.find(state.entries, state.entry, &(&1.id == state.entry.id))

          %{state | entry: entry}

        state.reader ->
          %{state | unread: Tayori.unread_count(state.reader)}

        true ->
          state
      end

    state = %{state | announcement: Tayori.Announcements.current(reader_of(state))}
    {:halt, put_state(socket, state)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  # The first page of the list, with the reactions of its entries.
  defp load(state, limit \\ nil) do
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

  defp shown(%{entry: nil, entries: entries}), do: entries
  defp shown(%{entry: entry, entries: entries}), do: [entry | entries]

  defp reactions(state, entries \\ nil) do
    if :reactions in state.features do
      ids = Enum.map(entries || shown(state), & &1.id) |> Enum.uniq()
      %{state | reactions: Tayori.Reactions.for_entries(reader_of(state), ids)}
    else
      state
    end
  end

  defp track(state, entries) do
    if :analytics in state.features do
      for entry <- entries, do: Tayori.Views.track(state.reader, entry.id, "panel")
    end

    :ok
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  defp put_state(socket, state), do: assign(socket, :tayori, state)
end
