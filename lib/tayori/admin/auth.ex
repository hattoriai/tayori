defmodule Tayori.Admin.Auth do
  @moduledoc false
  # The library's on_mount of the admin's live session, after the app's:
  # it takes the admin and their access from the session (read from the
  # request of the page by Tayori.Router.session/3) and the options from
  # the mount, and stops those who may not see the admin. It keeps the
  # count of the inbox's new changes for the bar, as the pages that follow
  # Tayori's events hear of them.
  #
  # The pages of a module that is off are not there: a 404, as for an
  # admin who may not see the admin. Without the changelog, the admin's
  # first page is the campaigns.

  use PhoenixMountable.Path, mountable: Tayori.Router

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView

  alias Tayori.Admin.{CategoriesLive, EntriesLive, EntryLive, InboxLive}
  alias Tayori.Config
  alias Tayori.Router.Page

  @changelog [EntriesLive, EntryLive, InboxLive, CategoriesLive]

  def on_mount(:default, _params, session, socket) do
    options = socket.assigns.mount.options

    socket =
      assign(socket,
        resolver: options.resolver,
        storage: options.storage,
        page_path: Page.path_from(socket.assigns.mount),
        theme: options.theme,
        user: session["user"],
        access: session["access"],
        time_zone: time_zone(socket),
        locale: locale(socket),
        config: Config.get()
      )

    changelog? = Config.module?(socket.assigns.config, :changelog)

    case socket.assigns.access do
      access when access in [:all, :read_only] and not changelog? ->
        cond do
          socket.view == EntriesLive -> {:halt, redirect(socket, to: ~m"/campaigns")}
          socket.view in @changelog -> raise Tayori.Admin.NotFound
          true -> {:cont, assign(socket, inbox_new: 0)}
        end

      access when access in [:all, :read_only] ->
        {:cont,
         socket
         |> assign(inbox_new: Tayori.Inbox.pending_count())
         |> attach_hook(:tayori_inbox, :handle_info, &count_inbox/2)}

      {:forbidden, path} when is_binary(path) ->
        {:halt, redirect(socket, to: path)}

      _forbidden ->
        raise Tayori.Admin.NotFound
    end
  end

  defp count_inbox({Tayori, :inbox, _id}, socket),
    do: {:cont, assign(socket, inbox_new: Tayori.Inbox.pending_count())}

  defp count_inbox(_message, socket), do: {:cont, socket}

  # The admin's own time zone, which their browser gives on connect: the
  # times of the admin are in it, when the app's time zone database knows
  # it (Elixir's own knows only UTC; an app with tz or tzdata knows all).
  defp time_zone(socket) do
    with %{"time_zone" => zone} when is_binary(zone) and byte_size(zone) < 64 <-
           connected?(socket) && get_connect_params(socket),
         {:ok, _now} <- DateTime.now(zone) do
      zone
    else
      _ -> "Etc/UTC"
    end
  end

  # The admin's language, from their browser: a BCP 47 tag, for the date
  # picker.
  defp locale(socket) do
    case connected?(socket) && get_connect_params(socket) do
      %{"locale" => locale} when is_binary(locale) ->
        if locale =~ ~r/\A[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}\z/, do: locale, else: "en"

      _ ->
        "en"
    end
  end
end

defmodule Tayori.Admin.NotFound do
  @moduledoc false
  # An admin who may not see the admin gets a 404, as if it were not there.
  defexception message: "not found", plug_status: 404
end
