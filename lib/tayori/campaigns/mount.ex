defmodule Tayori.Campaigns.Mount do
  @moduledoc """
  The addresses the campaigns' letters link to, mounted with
  `Tayori.Router.tayori_mail/2` at the `:url` of `:campaigns`
  (`Tayori.Config`):

      pipeline :letters do
        plug :accepts, ["html", "json"]
      end

      scope "/" do
        pipe_through :letters
        tayori_mail "/letters"
      end

  ## The routes

    * `GET /unsubscribe/:token` - a small page, in the person's language,
      that asks to unsubscribe from the letter's purpose, or from
      everything.
    * `POST /unsubscribe/:token` - unsubscribes: from the page's form
      (`all=1` for everything), or with one click from a mail client
      (`List-Unsubscribe=One-Click`, RFC 8058), which gets an empty 200.
    * `POST /webhooks/:provider` - a mail provider's events
      (`Tayori.Campaigns.Provider`): 404 for a provider not in
      `:providers`, 401 when it is not the provider's, 200 when handled.

  The mount takes no session and no CSRF token: a mail client's one-click
  unsubscribe and a provider's webhook have neither. Each request proves
  itself: the token of the link is signed, and the webhook is signed or
  authenticated. Mount it in a pipeline without `:protect_from_forgery`,
  as the JSON API of machines is.

  The webhook's signature is of the body as it was sent. An endpoint
  whose `Plug.Parsers` reads JSON reads it before the router: give it
  `body_reader: {PhoenixMountable.RawBody, :read_body, [MyAppWeb.Router]}`
  (see `Tayori.RawBody`).

  Without the `:campaigns` module, every route is a 404.
  """

  @behaviour Plug

  use Phoenix.Component
  # The webhooks' bodies as they were sent, kept by the endpoint's reader.
  use PhoenixMountable.RawBody, only: [:webhook]

  import Ecto.Query, only: [from: 2]
  import Plug.Conn, except: [assign: 3]
  import Tayori.Icons, only: [icon: 1]

  alias Phoenix.HTML.Safe
  alias Tayori.{Campaigns, Config, Messages, RawBody}
  alias Tayori.Campaigns.{Delivery, Letters, Webhooks}

  require Logger

  @compile {:no_warn_undefined, [Tayori.Campaigns.Letters]}

  @max_webhook_body 1_000_000

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, action) do
    config = Config.get()

    if Config.module?(config, :campaigns),
      do: handle(action, conn, config),
      else: not_found(conn)
  end

  # ── Unsubscribing ───────────────────────────────────────────────

  defp handle(:unsubscribe, conn, config) do
    conn = fetch_query_params(conn)

    case Letters.verify(conn.path_params["token"]) do
      {:ok, %{email: email, purpose: purpose}} ->
        page(conn, config, 200, email, %{state: :ask, email: email, purpose: purpose})

      :error ->
        page(conn, config, 404, nil, %{state: :invalid})
    end
  end

  defp handle(:unsubscribe_post, conn, config) do
    conn = fetch_query_params(conn)
    {body, conn} = read_form(conn)
    one_click? = body["List-Unsubscribe"] == "One-Click"

    case {Letters.verify(conn.path_params["token"]), one_click?} do
      {{:ok, %{email: email, purpose: purpose}}, true} ->
        :ok = Campaigns.suppress(email, purpose, "unsubscribed")
        conn |> send_resp(200, "") |> halt()

      {{:ok, %{email: email, purpose: purpose}}, false} ->
        purpose = if body["all"] in ["1", "true"], do: "all", else: purpose
        :ok = Campaigns.suppress(email, purpose, "unsubscribed")
        page(conn, config, 200, email, %{state: :done, email: email, purpose: purpose})

      {:error, true} ->
        conn |> send_resp(404, "") |> halt()

      {:error, false} ->
        page(conn, config, 404, nil, %{state: :invalid})
    end
  end

  # ── Webhooks ────────────────────────────────────────────────────

  defp handle(:webhook, conn, config) do
    case Webhooks.provider(config, conn.path_params["provider"]) do
      nil -> not_found(conn)
      {module, opts} -> webhook(conn, config, module, opts)
    end
  end

  defp webhook(conn, config, module, opts) do
    with {:ok, body, conn} <- sent_body(conn),
         {:verify, :ok} <- {:verify, module.verify(conn, body, opts)},
         {:ok, %{} = payload} <- JSON.decode(body) do
      json(conn, 200, %{handled: Webhooks.handle(config, module, payload)})
    else
      {:verify, _} -> json(conn, 401, %{error: "unauthorized"})
      {:error, status, error} -> json(conn, status, %{error: error})
      _not_json -> json(conn, 400, %{error: "invalid_json"})
    end
  end

  defp sent_body(conn) do
    case RawBody.fetch(conn, @max_webhook_body) do
      {:ok, body, conn} ->
        {:ok, body, conn}

      {:error, :no_raw_body} ->
        Logger.error(
          "Tayori cannot check a mail provider's webhook: the endpoint read the body before it. " <>
            "Give Plug.Parsers `body_reader: {PhoenixMountable.RawBody, :read_body, [MyAppWeb.Router]}`."
        )

        {:error, 500, "no_raw_body"}

      {:error, :too_large} ->
        {:error, 413, "too_large"}

      {:error, _reason} ->
        {:error, 400, "unreadable"}
    end
  end

  # ── The page ────────────────────────────────────────────────────

  defp page(conn, config, status, email, assigns) do
    mount = conn.assigns.mount
    locale = locale(conn, config, email)
    words = Messages.for_locale(locale)

    assigns =
      Map.merge(assigns, %{
        __changed__: nil,
        words: words,
        locale: locale,
        name: name(config),
        action: PhoenixMountable.Path.path(conn, "/unsubscribe/" <> conn.path_params["token"]),
        css: css(mount),
        theme: mount.options[:theme] || :tayori,
        nonce: mount.csp_nonces[:style]
      })

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("x-robots-tag", "noindex")
    |> send_resp(status, Safe.to_iodata(document(assigns)))
    |> halt()
  end

  defp document(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@locale} class="tayori-auto" data-tayori-theme={@theme}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <meta name="robots" content="noindex" />
        <title>{@words["unsubscribe"]}</title>
        <link rel="stylesheet" href={@css} nonce={@nonce} />
      </head>
      <body class="tayori-page">
        <div class="tayori-shell">
          <header class="tayori-masthead">
            <p class="tayori-eyebrow">{@name}</p>
            <h1 class="tayori-page-title">{@words["unsubscribe"]}</h1>
            <.content {assigns} />
          </header>
        </div>
      </body>
    </html>
    """
  end

  defp content(%{state: :invalid} = assigns) do
    ~H"""
    <p class="tayori-notice tayori-notice-error" role="status">
      <.icon name="circle-x" />{@words["invalidLink"]}
    </p>
    """
  end

  defp content(%{state: :ask} = assigns) do
    ~H"""
    <p class="tayori-page-description">{question(@words, @purpose, @email)}</p>
    <form class="tayori-masthead-actions" action={@action} method="post">
      <button type="submit" class="tayori-cta">{@words["unsubscribe"]}</button>
      <button
        :if={@purpose != "all"}
        type="submit"
        name="all"
        value="1"
        class="tayori-cta tayori-cta-quiet"
      >
        {@words["unsubscribeAll"]}
      </button>
    </form>
    """
  end

  defp content(%{state: :done} = assigns) do
    ~H"""
    <p class="tayori-notice" role="status">
      <.icon name="circle-check" />{if @purpose == "all",
        do: @words["unsubscribedAll"],
        else: @words["unsubscribedLetters"]}
    </p>
    <form :if={@purpose != "all"} class="tayori-masthead-actions" action={@action} method="post">
      <button type="submit" name="all" value="1" class="tayori-cta tayori-cta-quiet">
        {@words["unsubscribeAll"]}
      </button>
    </form>
    """
  end

  defp question(words, purpose, email) do
    key =
      case purpose do
        "marketing" -> "unsubscribeMarketing"
        "product" -> "unsubscribeProduct"
        "all" -> "unsubscribeEverything"
      end

    String.replace(words[key], "{email}", email)
  end

  defp name(%Config{campaigns: %{from: {name, _address}}}), do: name
  defp name(%Config{campaigns: %{url: url}}), do: URI.parse(url).host

  defp css(mount) do
    case mount.options[:theme] do
      :sumi -> PhoenixMountable.Assets.url(mount, :sumi)
      _tayori -> PhoenixMountable.Assets.url(mount, :css)
    end
  end

  # The person's language: `?lang=`, else that of the last letter to the
  # address, else the browser's, else the app's first.
  defp locale(conn, config, email) do
    known = config.locales

    [conn.query_params["lang"], email && last_locale(config, email) | accepted(conn)]
    |> Enum.find_value(Config.default_locale(config), fn
      locale when is_binary(locale) ->
        Enum.find(known, &(&1 == locale)) ||
          Enum.find(known, &(language(&1) == language(locale)))

      _ ->
        nil
    end)
  end

  # The deliveries keep the address lowercased, as the token does.
  defp last_locale(config, email) do
    email = Campaigns.normalize(email)

    from(d in Delivery,
      where: d.email == ^email and not is_nil(d.locale),
      order_by: [desc: d.inserted_at],
      limit: 1,
      select: d.locale
    )
    |> config.repo.one(prefix: config.prefix)
  end

  defp accepted(conn) do
    conn
    |> get_req_header("accept-language")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim()))
    |> Enum.reject(&(&1 in ["", "*"]))
  end

  defp language(locale), do: locale |> String.split(["-", "_"]) |> hd() |> String.downcase()

  # ── Helpers ─────────────────────────────────────────────────────

  defp read_form(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        case Plug.Conn.read_body(conn, length: 8_000) do
          {:ok, body, conn} -> {decode_query(body), conn}
          _too_large -> {%{}, conn}
        end

      params ->
        {params, conn}
    end
  end

  # A mail client's body may be multipart, or anything: nothing then.
  defp decode_query(body) do
    URI.decode_query(body)
  rescue
    ArgumentError -> %{}
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(data))
    |> halt()
  end

  defp not_found(conn) do
    conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not Found") |> halt()
  end
end
