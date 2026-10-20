defmodule Tayori.Admin.Layouts do
  @moduledoc false
  # The admin's own document: its styles and script (the mount's assets),
  # and the meta tags its script reads to join the app's LiveView socket.

  use Phoenix.Component
  use PhoenixMountable.Path, mountable: Tayori.Router

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-tayori-theme={@mount.options.theme}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <PhoenixMountable.Layout.meta mount={@mount} />
        <meta name="robots" content="noindex, nofollow" />
        <title>{assigns[:page_title] || "News"} · Tayori</title>
        <link rel="icon" type="image/svg+xml" href={favicon()} />
        <PhoenixMountable.Layout.assets mount={@mount} />
      </head>
      <body class="tayori-admin">
        {@inner_content}
      </body>
    </html>
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
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <header class="ta-header">
      <.link navigate={~m"/"} class="ta-brand">
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
        <span>News</span>
      </.link>
      <nav class="ta-nav" aria-label="Admin">
        <.link navigate={~m"/"} aria-current={@page == :entries && "page"}>Entries</.link>
        <.link navigate={~m"/settings"} aria-current={@page == :settings && "page"}>
          Settings
        </.link>
      </nav>
    </header>
    <main class="ta-main">
      <div :for={{kind, message} <- @flash} class={"ta-flash ta-flash-#{kind}"} role="status">
        {message}
      </div>
      {render_slot(@inner_block)}
    </main>
    """
  end
end
