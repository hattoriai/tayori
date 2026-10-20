defmodule Tayori.Components do
  @moduledoc """
  The news in a LiveView: a button with the count of unread entries, and
  the panel it opens. They read `@tayori`, from `Tayori.Live`.

      <Tayori.Components.news_button tayori={@tayori} />
      <Tayori.Components.news_panel tayori={@tayori} />

  Put the button where the app's header has its icons, and the panel
  once in the layout (it is fixed to the side of the page). They need
  `tayori.css` (and `tayori-sumi.css` for Sumi), and the `Tayori` hook,
  which shows the dates in the reader's time zone and language (see the
  [In the app](in_app.md) guide).

  `news/1` is the list of entries alone, for a page of the app's own.
  """

  use Phoenix.Component

  alias Tayori.Entry

  attr :tayori, Tayori.Live.State, required: true
  attr :class, :any, default: nil, doc: "classes of the button, besides `tayori-button`"
  attr :label, :boolean, default: false, doc: "show the word \"What's new\" beside the icon"
  attr :rest, :global

  @doc """
  The button that opens the panel, with the count of unread entries. Its
  accessible name says the count ("What's new, 2 new updates").
  """
  def news_button(assigns) do
    ~H"""
    <button
      type="button"
      class={["tayori-button", @class]}
      phx-click="tayori:open"
      aria-haspopup="dialog"
      aria-expanded={to_string(@tayori.open)}
      aria-controls="tayori-panel"
      aria-label={label(@tayori)}
      {@rest}
    >
      <svg class="tayori-icon" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v11a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 17.5z" />
        <path d="m4 7 8 6 8-6" />
      </svg>
      <span :if={@label} class="tayori-button-label">{@tayori.messages["button"]}</span>
      <span :if={@tayori.unread > 0} class="tayori-badge" aria-hidden="true">
        {if @tayori.unread > 9, do: "9+", else: @tayori.unread}
      </span>
    </button>
    """
  end

  defp label(%{unread: 0, messages: messages}), do: messages["button"]

  defp label(%{unread: n, messages: messages}),
    do: messages["button"] <> ", " <> Tayori.Messages.unread(messages, n)

  attr :tayori, Tayori.Live.State, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  @doc """
  The panel of the news: the newest entries, with a "New" mark on those
  the reader had not seen, "Show more", and a link to the public page.
  Escape and a click outside close it.
  """
  def news_panel(assigns) do
    ~H"""
    <div
      :if={@tayori.open}
      id="tayori-panel"
      class={["tayori-panel", @class]}
      role="dialog"
      aria-modal="false"
      aria-labelledby="tayori-panel-title"
      phx-hook="Tayori"
      phx-window-keydown="tayori:close"
      phx-key="Escape"
      phx-click-away="tayori:close"
      lang={@tayori.locale}
      {@rest}
    >
      <header class="tayori-panel-header">
        <h2 id="tayori-panel-title">{@tayori.messages["title"]}</h2>
        <button
          type="button"
          class="tayori-close"
          phx-click="tayori:close"
          aria-label={@tayori.messages["close"]}
        >
          ×
        </button>
      </header>
      <div class="tayori-panel-body">
        <.news
          entries={@tayori.entries}
          seen_before={@tayori.seen_before}
          messages={@tayori.messages}
          page={@tayori.page}
        />
        <p :if={@tayori.entries == []} class="tayori-empty">{@tayori.messages["empty"]}</p>
        <button :if={@tayori.more} type="button" class="tayori-more" phx-click="tayori:more">
          {@tayori.messages["more"]}
        </button>
      </div>
      <footer :if={@tayori.page} class="tayori-panel-footer">
        <a href={@tayori.page}>{@tayori.messages["allNews"]}</a>
      </footer>
    </div>
    """
  end

  attr :entries, :list,
    required: true,
    doc: "entries with their `translation`, from `Tayori.news/2`"

  attr :messages, :map, default: nil, doc: "the words, from `Tayori.Messages.for_locale/2`"
  attr :seen_before, DateTime, default: nil, doc: "entries published after it are marked New"
  attr :page, :string, default: nil, doc: "the public page: each title links to its entry"
  attr :heading, :string, default: "h3", doc: "the element of the titles"

  @doc "A list of entries: their categories, date, title and body."
  def news(assigns) do
    assigns = assign_new(assigns, :messages, fn -> Tayori.Messages.for_locale("en") end)

    ~H"""
    <ol class="tayori-news">
      <li :for={entry <- @entries} id={"tayori-entry-#{entry.id}"}>
        <.entry
          entry={entry}
          new={new?(entry, @seen_before)}
          messages={@messages}
          href={@page && @page <> "/" <> entry.slug}
          heading={@heading}
        />
      </li>
    </ol>
    """
  end

  attr :entry, Entry, required: true
  attr :new, :boolean, default: false
  attr :messages, :map, required: true
  attr :href, :string, default: nil
  attr :heading, :string, default: "h3"

  @doc "One entry, in the translation `Tayori.news/2` chose for the reader."
  def entry(assigns) do
    ~H"""
    <article class="tayori-entry" lang={@entry.translation.locale}>
      <p class="tayori-entry-meta">
        <span :if={@new} class="tayori-new">{@messages["new"]}</span>
        <span :for={category <- @entry.categories} class="tayori-category">{category}</span>
        <time datetime={DateTime.to_iso8601(@entry.published_at)} data-tayori-time="date">
          {Tayori.Messages.date(@messages, @entry.published_at)}
        </time>
      </p>
      <.dynamic_tag tag_name={@heading} class="tayori-entry-title">
        <a :if={@href} href={@href}>{@entry.translation.title}</a>
        <span :if={!@href}>{@entry.translation.title}</span>
      </.dynamic_tag>
      <Kotoba.Components.kotoba_content
        :if={@entry.translation.body}
        content={@entry.translation.body}
        class="tayori-entry-body"
      />
    </article>
    """
  end

  defp new?(_entry, nil), do: false
  defp new?(%Entry{published_at: at}, seen_before), do: DateTime.compare(at, seen_before) == :gt
end
