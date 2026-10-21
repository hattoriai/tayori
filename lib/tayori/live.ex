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

  Without the `:changelog` module (`Tayori.Config`), the hook does
  nothing: `@tayori` is nil, and the components render nothing.

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

  alias Tayori.{Panel, Resolver}

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

  def on_mount(opts, params, session, socket) when is_list(opts) do
    if Tayori.Config.module?(Tayori.Config.get(), :changelog),
      do: mount(opts, params, session, socket),
      else: {:cont, assign(socket, :tayori, nil)}
  end

  defp mount(opts, _params, _session, socket) do
    resolver = Keyword.fetch!(opts, :resolver)
    reader = Resolver.reader(resolver, socket)
    state = Panel.new(reader, page: opts[:page], limit: Keyword.get(opts, :limit, 10))

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

    {:cont, assign(socket, :tayori, state)}
  end

  defp handle_event("tayori:open", _params, socket), do: update(socket, &Panel.open/1)
  defp handle_event("tayori:close", _params, socket), do: update(socket, &Panel.close/1)
  defp handle_event("tayori:more", _params, socket), do: update(socket, &Panel.more/1)
  defp handle_event("tayori:back", _params, socket), do: update(socket, &Panel.back/1)

  defp handle_event("tayori:filter", params, socket),
    do: update(socket, &Panel.filter(&1, blank(params["category"])))

  defp handle_event("tayori:show", %{"id" => id}, socket) do
    case Panel.show(socket.assigns.tayori, id, "panel") do
      {:ok, state} -> {:halt, put_state(socket, state)}
      :error -> {:halt, socket}
    end
  end

  defp handle_event("tayori:react", %{"id" => id, "emoji" => emoji}, socket),
    do: update(socket, &Panel.react(&1, id, emoji))

  defp handle_event("tayori:dismiss", %{"id" => id}, socket),
    do: update(socket, &Panel.dismiss(&1, id))

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp update(socket, fun), do: {:halt, put_state(socket, fun.(socket.assigns.tayori))}

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

    if state.open and Enum.any?(Panel.shown(state), &(&1.id == id)),
      do: {:halt, put_state(socket, Panel.reactions(state))},
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
          state = Panel.load(state, max(length(state.entries), state.limit))

          entry =
            state.entry &&
              Enum.find(state.entries, state.entry, &(&1.id == state.entry.id))

          %{state | entry: entry}

        state.reader ->
          %{state | unread: Tayori.unread_count(state.reader)}

        true ->
          state
      end

    state = %{state | announcement: Tayori.Announcements.current(Panel.reader_of(state))}
    {:halt, put_state(socket, state)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  defp put_state(socket, state), do: assign(socket, :tayori, state)
end
