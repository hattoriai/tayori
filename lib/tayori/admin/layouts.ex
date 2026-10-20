defmodule Tayori.Admin.Layouts do
  @moduledoc false
  # The admin's own document (its styles and script, the mount's assets,
  # and the meta tags its script reads to join the app's LiveView socket),
  # and the shell of its pages: the bar, the navigation, the footer.

  use Phoenix.Component
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Icons, only: [icon: 1]

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-tayori-theme={@mount.options.theme}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <PhoenixMountable.Layout.meta mount={@mount} />
        <meta name="robots" content="noindex, nofollow" />
        <title>{assigns[:page_title] || "News"} · Tayori</title>
        <link rel="icon" type="image/svg+xml" href={favicon()} />
        {appearance_script(@mount.csp_nonces[:script])}
        <PhoenixMountable.Layout.assets
          mount={@mount}
          only={if @mount.options.theme == :sumi, do: [:sumi, :js], else: [:css, :js]}
        />
      </head>
      <body class={["tayori-admin", "tayori-admin-#{@mount.options.theme}"]}>
        {@inner_content}
      </body>
    </html>
    """
  end

  # Light, dark or the system's, as the admin chose in this browser: set
  # before the first paint.
  # HEEx does not interpolate in a script: the tag is made whole.
  defp appearance_script(nonce) do
    nonce =
      if nonce,
        do: ~s( nonce="#{Phoenix.HTML.html_escape(nonce) |> Phoenix.HTML.safe_to_string()}"),
        else: ""

    Phoenix.HTML.raw("<script#{nonce}>" <> appearance_js() <> "</script>")
  end

  defp appearance_js do
    """
    try{var a=localStorage.getItem("tayori-appearance");if(a==="dark"||a==="light")document.documentElement.dataset.theme=a;else if(matchMedia("(prefers-color-scheme: dark)").matches)document.documentElement.dataset.theme="dark"}catch(e){}
    """
  end

  # The sealed letter, so that the tab of the admin has its own icon and
  # never asks the app for /favicon.ico.
  @favicon "data:image/svg+xml," <>
             URI.encode(
               ~s|<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 112 112"><defs><mask id="m"><rect width="112" height="112" fill="white"/><path d="M16 30L56 60L96 30" fill="none" stroke="black" stroke-width="3.5"/><circle cx="56" cy="60" r="14"/></mask></defs><path mask="url(#m)" fill="#0a0a0b" d="M26 16H86Q96 16 96 26V86Q96 96 86 96H26Q16 96 16 86V26Q16 16 26 16Z"/><circle cx="56" cy="60" r="10.5" fill="#e84a1c"/></svg>|,
               &URI.char_unreserved?/1
             )

  defp favicon, do: @favicon

  attr :page, :atom, required: true
  attr :flash, :map, default: %{}
  attr :access, :any, default: :all
  attr :wide, :boolean, default: false
  attr :inbox, :integer, default: 0, doc: "The inbox's new changes, for the public."
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <div class="ta-app">
      <header class="ta-bar">
        <div class="ta-bar-inner">
          <.link navigate={~m"/"} class="ta-brand" aria-label="Tayori, the entries">
            <.mark />
            <span class="ta-wordmark">Tayori</span>
          </.link>
          <nav class="ta-nav" aria-label="Admin">
            <.link navigate={~m"/"} aria-current={@page == :entries && "page"}>
              <.icon name="newspaper" /><span class="ta-nav-label">Entries</span>
            </.link>
            <.link navigate={~m"/inbox"} aria-current={@page == :inbox && "page"}>
              <.icon name="inbox" /><span class="ta-nav-label">Inbox</span>
              <span :if={@inbox > 0} class="ta-nav-count" title={"#{@inbox} new"}>{@inbox}</span>
            </.link>
            <.link navigate={~m"/categories"} aria-current={@page == :categories && "page"}>
              <.icon name="tags" /><span class="ta-nav-label">Categories</span>
            </.link>
            <.link navigate={~m"/settings"} aria-current={@page == :settings && "page"}>
              <.icon name="settings" /><span class="ta-nav-label">Settings</span>
            </.link>
          </nav>
          <div class="ta-bar-actions">
            <.appearance />
            <.link :if={@access == :all} navigate={~m"/new"} class="ta-button ta-primary">
              <.icon name="plus" /><span class="ta-bar-label">New entry</span>
            </.link>
          </div>
        </div>
      </header>
      <main class={["ta-main", @wide && "ta-main-wide"]}>
        <div :if={@flash != %{}} class="ta-flashes">
          <div
            :for={{kind, message} <- @flash}
            class={"ta-flash ta-flash-#{kind}"}
            role="status"
            id={"flash-#{kind}"}
            phx-click="lv:clear-flash"
            phx-value-key={kind}
          >
            <.icon name={if kind == "error", do: "triangle-alert", else: "circle-check"} />
            <span>{message}</span>
          </div>
        </div>
        {render_slot(@inner_block)}
      </main>
      <footer class="ta-footer">
        <span>Tayori v{Tayori.version()}</span>
        <span class="ta-made">Made by Hattori AI</span>
      </footer>
    </div>
    """
  end

  # Light, dark or the system's, kept in this browser by the admin's script.
  defp appearance(assigns) do
    ~H"""
    <div class="ta-appearance" id="ta-appearance" phx-hook="TayoriAppearance" phx-update="ignore">
      <button type="button" class="ta-icon-button" aria-label="Appearance" aria-haspopup="menu">
        <.icon name="sun" class="ta-when-light" />
        <.icon name="moon" class="ta-when-dark" />
      </button>
      <div class="ta-menu" role="menu" hidden>
        <p class="ta-menu-label">Appearance</p>
        <button type="button" role="menuitemradio" data-appearance="light">
          <.icon name="sun" />Light
        </button>
        <button type="button" role="menuitemradio" data-appearance="dark">
          <.icon name="moon" />Dark
        </button>
        <button type="button" role="menuitemradio" data-appearance="system">
          <.icon name="monitor" />System
        </button>
      </div>
    </div>
    """
  end

  @doc "The sealed letter: Tayori's mark."
  def mark(assigns) do
    ~H"""
    <svg viewBox="0 0 112 112" aria-hidden="true" class="ta-mark">
      <defs>
        <mask id="ta-letter" maskUnits="userSpaceOnUse" x="0" y="0" width="112" height="112">
          <rect width="112" height="112" fill="white" />
          <path
            d="M16 30L56 60L96 30"
            fill="none"
            stroke="black"
            stroke-width="3.5"
            stroke-linejoin="round"
          />
          <circle cx="56" cy="60" r="14" fill="black" />
        </mask>
      </defs>
      <path
        mask="url(#ta-letter)"
        fill="currentColor"
        d="M26 16H86Q96 16 96 26V86Q96 96 86 96H26Q16 96 16 86V26Q16 16 26 16Z"
      />
      <circle cx="56" cy="60" r="10.5" class="ta-seal" />
    </svg>
    """
  end
end
