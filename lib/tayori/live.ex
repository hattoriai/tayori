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
    The `@tayori` assign: the `:reader` (nil for a visitor), its
    `:unread` count, whether the panel is `:open`, its `:entries`, whether
    there are `:more`, the time the reader had seen the news until
    (`:seen_before`, for the "New" mark), the `:page` path, the `:locale`
    and its `:messages`.
    """

    @type t :: %__MODULE__{
            reader: Tayori.Reader.t() | nil,
            unread: non_neg_integer(),
            open: boolean(),
            entries: [Tayori.Entry.t()],
            more: boolean(),
            seen_before: DateTime.t() | nil,
            page: String.t() | nil,
            locale: String.t(),
            messages: map(),
            limit: pos_integer()
          }

    defstruct reader: nil,
              unread: 0,
              open: false,
              entries: [],
              more: false,
              seen_before: nil,
              page: nil,
              locale: "en",
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
      messages: Tayori.Messages.for_locale(locale),
      limit: Keyword.get(opts, :limit, 10)
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

    {:cont, assign(socket, :tayori, state)}
  end

  defp handle_event("tayori:open", _params, socket) do
    state = socket.assigns.tayori
    reader = state.reader || Reader.visitor(state.locale)
    seen_before = state.reader && Tayori.seen_at(state.reader)
    entries = Tayori.news(reader, limit: state.limit + 1)

    if state.reader, do: Tayori.mark_seen(state.reader)

    {:halt,
     put_state(socket, %{
       state
       | open: true,
         unread: 0,
         seen_before: seen_before,
         entries: Enum.take(entries, state.limit),
         more: length(entries) > state.limit
     })}
  end

  defp handle_event("tayori:close", _params, socket) do
    {:halt, put_state(socket, %{socket.assigns.tayori | open: false})}
  end

  defp handle_event("tayori:more", _params, socket) do
    state = socket.assigns.tayori

    more =
      Tayori.news(state.reader || Reader.visitor(state.locale),
        limit: state.limit + 1,
        before: List.last(state.entries)
      )

    {:halt,
     put_state(socket, %{
       state
       | entries: state.entries ++ Enum.take(more, state.limit),
         more: length(more) > state.limit
     })}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info({Tayori, :seen, _id}, socket) do
    {:halt, put_state(socket, %{socket.assigns.tayori | unread: 0})}
  end

  defp handle_info({Tayori, event, _id}, socket) when event in [:published, :changed] do
    state = socket.assigns.tayori

    state =
      cond do
        state.open ->
          # The panel shows the news as it is: what is published while it
          # is open is seen.
          reader = state.reader || Reader.visitor(state.locale)
          if state.reader, do: Tayori.mark_seen(state.reader)
          entries = Tayori.news(reader, limit: max(length(state.entries), state.limit) + 1)
          %{state | entries: Enum.take(entries, max(length(state.entries), state.limit))}

        state.reader ->
          %{state | unread: Tayori.unread_count(state.reader)}

        true ->
          state
      end

    {:halt, put_state(socket, state)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp put_state(socket, state), do: assign(socket, :tayori, state)
end
