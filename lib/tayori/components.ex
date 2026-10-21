defmodule Tayori.Components do
  @moduledoc """
  The news in a LiveView: a button with the count of unread entries, the
  panel it opens, and the announcement of the moment. They read `@tayori`,
  from `Tayori.Live`.

      <Tayori.Components.news_button tayori={@tayori} />
      <Tayori.Components.news_panel tayori={@tayori} />
      <Tayori.Components.announcement tayori={@tayori} />

  Put the button where the app's header has its icons, and the panel and
  the announcement once in the layout (they are fixed to the page). They
  need `tayori.css` (and `tayori-sumi.css` for Sumi), and the `Tayori`
  hook, which shows the dates in the reader's time zone and language (see
  the [In the app](in_app.md) guide).

  The panel lists the newest entries as cards: a cover, the categories,
  the date, the title and the summary. A card opens its entry in the
  panel, whole, with its reactions. Escape goes back, then closes.

  `news/1` and `entry/1` are the list and an entry alone, for a page of
  the app's own.

  Without the `:changelog` module, `@tayori` is nil, and the button, the
  panel and the announcement render nothing.
  """

  use Phoenix.Component

  import Tayori.Icons, only: [icon: 1]

  alias Tayori.{Category, Entry, Messages}

  attr :tayori, :any, required: true, doc: "`@tayori`, a `Tayori.Live.State`, or nil"
  attr :class, :any, default: nil, doc: "classes of the button, besides `tayori-button`"
  attr :label, :boolean, default: false, doc: "show the word \"What's new\" beside the icon"
  attr :rest, :global

  @doc """
  The button that opens the panel, with the count of unread entries. Its
  accessible name says the count ("What's new, 2 new updates").
  """
  def news_button(%{tayori: nil} = assigns), do: ~H""

  def news_button(assigns) do
    ~H"""
    <button
      type="button"
      class={["tayori-button", @label && "tayori-button-labelled", @class]}
      phx-click="tayori:open"
      aria-haspopup="dialog"
      aria-expanded={to_string(@tayori.open)}
      aria-controls="tayori-panel"
      aria-label={label(@tayori)}
      {@rest}
    >
      <.icon name="sparkles" />
      <span :if={@label} class="tayori-button-label">{@tayori.messages["button"]}</span>
      <span :if={@tayori.unread > 0} class="tayori-badge" aria-hidden="true">
        {if @tayori.unread > 9, do: "9+", else: @tayori.unread}
      </span>
    </button>
    """
  end

  defp label(%{unread: 0, messages: messages}), do: messages["button"]

  defp label(%{unread: n, messages: messages}),
    do: messages["button"] <> ", " <> Messages.unread(messages, n)

  attr :tayori, :any, required: true, doc: "`@tayori`, a `Tayori.Live.State`, or nil"
  attr :class, :any, default: nil
  attr :rest, :global

  @doc """
  The panel of the news: the newest entries as cards, the pinned ones
  first, with a "New" mark on those the reader had not seen; the
  categories to filter by; an entry open whole; "Show more", and a link
  to the public page. Escape goes back to the list, then closes; so does
  a click outside.
  """
  def news_panel(%{tayori: nil} = assigns), do: ~H""

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
      phx-window-keydown={if @tayori.entry, do: "tayori:back", else: "tayori:close"}
      phx-key="Escape"
      phx-click-away="tayori:close"
      lang={@tayori.locale}
      {@rest}
    >
      <header class="tayori-panel-header">
        <button
          :if={@tayori.entry}
          type="button"
          class="tayori-icon-button"
          phx-click="tayori:back"
          aria-label={@tayori.messages["back"]}
        >
          <.icon name="arrow-left" />
        </button>
        <h2 id="tayori-panel-title">{@tayori.messages["title"]}</h2>
        <a
          :if={@tayori.page}
          href={@tayori.page}
          class="tayori-icon-button"
          aria-label={@tayori.messages["allNews"]}
          title={@tayori.messages["allNews"]}
        >
          <.icon name="arrow-up-right" />
        </a>
        <button
          type="button"
          class="tayori-icon-button tayori-close"
          phx-click="tayori:close"
          aria-label={@tayori.messages["close"]}
        >
          <.icon name="x" />
        </button>
      </header>

      <div :if={@tayori.entry} class="tayori-panel-body" id="tayori-panel-entry">
        <.entry
          entry={@tayori.entry}
          messages={@tayori.messages}
          categories={@tayori.categories}
          locales={@tayori.locales}
          new={new?(@tayori.entry, @tayori.seen_before)}
          heading="h3"
          href={@tayori.page && @tayori.page <> "/" <> @tayori.entry.slug}
        >
          <:footer :if={:reactions in @tayori.features}>
            <.reactions
              entry_id={@tayori.entry.id}
              reactions={@tayori.reactions}
              emoji={@tayori.emoji}
              messages={@tayori.messages}
              disabled={is_nil(@tayori.reader)}
            />
          </:footer>
        </.entry>
      </div>

      <div :if={!@tayori.entry} class="tayori-panel-body" id="tayori-panel-list">
        <.category_filter
          :if={map_size(@tayori.categories) > 0}
          categories={@tayori.categories}
          current={@tayori.category}
          messages={@tayori.messages}
          locale={@tayori.locale}
          locales={@tayori.locales}
        />
        <ol :if={@tayori.entries != []} class="tayori-cards">
          <li :for={entry <- @tayori.entries} id={"tayori-entry-#{entry.id}"}>
            <.card
              entry={entry}
              messages={@tayori.messages}
              categories={@tayori.categories}
              locales={@tayori.locales}
              new={new?(entry, @tayori.seen_before)}
              reactions={:reactions in @tayori.features && @tayori.reactions}
            />
          </li>
        </ol>
        <div :if={@tayori.entries == []} class="tayori-empty">
          <.icon name="inbox" />
          <p>{@tayori.messages["empty"]}</p>
        </div>
        <button :if={@tayori.more} type="button" class="tayori-more" phx-click="tayori:more">
          {@tayori.messages["more"]}
        </button>
      </div>

      <footer class="tayori-panel-footer">
        <span class="tayori-hint">
          <kbd class="tayori-kbd">Esc</kbd>
          {if @tayori.entry, do: @tayori.messages["back"], else: @tayori.messages["close"]}
        </span>
        <a :if={@tayori.page} href={@tayori.page}>
          {@tayori.messages["allNews"]} <.icon name="arrow-right" />
        </a>
      </footer>
    </div>
    """
  end

  attr :categories, :map, required: true
  attr :current, :string, default: nil
  attr :messages, :map, required: true
  attr :locale, :string, required: true
  attr :locales, :list, required: true
  attr :event, :string, default: "tayori:filter"

  @doc false
  def category_filter(assigns) do
    assigns =
      assign(assigns, :sorted, Enum.sort_by(Map.values(assigns.categories), & &1.position))

    ~H"""
    <nav class="tayori-filter" aria-label={@messages["categories"]}>
      <button
        type="button"
        class="tayori-chip"
        aria-pressed={to_string(@current == nil)}
        phx-click={@event}
        phx-value-category=""
      >
        {@messages["all"]}
      </button>
      <button
        :for={category <- @sorted}
        type="button"
        class="tayori-chip"
        data-color={category.color}
        aria-pressed={to_string(@current == category.key)}
        phx-click={@event}
        phx-value-category={category.key}
      >
        <span class="tayori-dot" aria-hidden="true"></span>
        {Category.name(category, @locale, @locales)}
      </button>
    </nav>
    """
  end

  attr :entries, :list,
    required: true,
    doc: "entries with their `translation`, from `Tayori.news/2`"

  attr :messages, :map, default: nil, doc: "the words, from `Tayori.Messages.for_locale/2`"
  attr :seen_before, DateTime, default: nil, doc: "entries published after it are marked New"
  attr :page, :string, default: nil, doc: "the public page: each title links to its entry"
  attr :heading, :string, default: "h3", doc: "the element of the titles"

  attr :categories, :map,
    default: %{},
    doc: "the categories by key (`Tayori.Categories.by_key/0`)"

  @doc "A list of entries, whole: their cover, categories, date, title and body."
  def news(assigns) do
    assigns = assign_new(assigns, :messages, fn -> Messages.for_locale("en") end)

    ~H"""
    <ol class="tayori-news">
      <li :for={entry <- @entries} id={"tayori-entry-#{entry.id}"}>
        <.entry
          entry={entry}
          new={new?(entry, @seen_before)}
          messages={@messages}
          categories={@categories}
          href={@page && @page <> "/" <> entry.slug}
          heading={@heading}
        />
      </li>
    </ol>
    """
  end

  attr :entry, Entry, required: true
  attr :messages, :map, required: true
  attr :categories, :map, default: %{}
  attr :locales, :list, default: []
  attr :new, :boolean, default: false
  attr :reactions, :any, default: false
  attr :event, :string, default: "tayori:show"

  @doc false
  # An entry as a card of the panel: the whole card opens it.
  def card(assigns) do
    ~H"""
    <article
      class={["tayori-card", @entry.pinned_at && "tayori-card-pinned"]}
      lang={@entry.translation.locale}
    >
      <.cover :if={@entry.cover} cover={@entry.cover} class="tayori-card-cover" />
      <.meta
        entry={@entry}
        new={@new}
        messages={@messages}
        categories={@categories}
        locales={@locales}
      />
      <h3 class="tayori-card-title">
        <button type="button" phx-click={@event} phx-value-id={@entry.id}>
          {@entry.translation.title}
        </button>
      </h3>
      <p :if={summary(@entry)} class="tayori-card-summary">{summary(@entry)}</p>
      <.reaction_counts :if={@reactions} entry_id={@entry.id} reactions={@reactions} />
    </article>
    """
  end

  defp summary(%Entry{translation: %{summary: summary}}) when is_binary(summary), do: summary

  defp summary(%Entry{translation: %{body: %Kotoba.Content{text: text}}})
       when is_binary(text) and text != "" do
    text = String.replace(text, ~r/\s+/, " ")
    if String.length(text) > 180, do: String.slice(text, 0, 177) <> "…", else: text
  end

  defp summary(_entry), do: nil

  attr :entry, Entry, required: true
  attr :new, :boolean, default: false
  attr :messages, :map, required: true
  attr :categories, :map, default: %{}
  attr :locales, :list, default: []

  @doc false
  def meta(assigns) do
    ~H"""
    <p class="tayori-meta">
      <span :if={@entry.pinned_at} class="tayori-pinned">
        <.icon name="pin" />{@messages["pinned"]}
      </span>
      <span :if={@new} class="tayori-new" title={@messages["new"]}>
        <span class="tayori-visually-hidden">{@messages["new"]}</span>
      </span>
      <.category
        :for={key <- @entry.categories}
        key={key}
        categories={@categories}
        locale={@entry.translation.locale}
        locales={@locales}
      />
      <time
        :if={@entry.published_at}
        datetime={DateTime.to_iso8601(@entry.published_at)}
        data-tayori-time="date"
      >
        {Messages.date(@messages, @entry.published_at)}
      </time>
    </p>
    """
  end

  attr :key, :string, required: true
  attr :categories, :map, default: %{}
  attr :locale, :string, default: nil
  attr :locales, :list, default: []

  @doc "A category's pill, in its colour."
  def category(assigns) do
    assigns = assign(assigns, :category, Map.get(assigns.categories, assigns.key))

    ~H"""
    <span class="tayori-category" data-color={(@category && @category.color) || "gray"}>
      {if @category, do: Category.name(@category, @locale, @locales), else: @key}
    </span>
    """
  end

  attr :cover, :map, required: true
  attr :class, :string, default: nil
  attr :loading, :string, default: "lazy"

  @doc "An entry's cover image."
  def cover(assigns) do
    ~H"""
    <figure class={["tayori-cover", @class]}>
      <img
        src={@cover["url"]}
        alt={@cover["alt"] || ""}
        width={@cover["width"]}
        height={@cover["height"]}
        loading={@loading}
        decoding="async"
      />
    </figure>
    """
  end

  attr :entry, Entry, required: true
  attr :new, :boolean, default: false
  attr :messages, :map, required: true
  attr :categories, :map, default: %{}
  attr :locales, :list, default: []
  attr :href, :string, default: nil
  attr :heading, :string, default: "h3"
  attr :cover, :boolean, default: true
  slot :footer

  @doc "One entry, whole, in the translation `Tayori.news/2` chose for the reader."
  def entry(assigns) do
    ~H"""
    <article class="tayori-entry" lang={@entry.translation.locale}>
      <.meta
        entry={@entry}
        new={@new}
        messages={@messages}
        categories={@categories}
        locales={@locales}
      />
      <.dynamic_tag tag_name={@heading} class="tayori-entry-title">
        <a :if={@href} href={@href}>{@entry.translation.title}</a>
        <span :if={!@href}>{@entry.translation.title}</span>
      </.dynamic_tag>
      <p :if={@entry.translation.summary} class="tayori-entry-summary">
        {@entry.translation.summary}
      </p>
      <.cover :if={@cover && @entry.cover} cover={@entry.cover} class="tayori-entry-cover" />
      <Kotoba.Components.kotoba_content
        :if={@entry.translation.body}
        content={@entry.translation.body}
        class="tayori-entry-body"
      />
      <footer :if={@footer != []} class="tayori-entry-footer">{render_slot(@footer)}</footer>
    </article>
    """
  end

  attr :entry_id, :string, required: true

  attr :reactions, :any,
    required: true,
    doc: "`{counts, mine}` of `Tayori.Reactions.for_entries/2`"

  attr :emoji, :list, required: true
  attr :messages, :map, required: true
  attr :disabled, :boolean, default: false, doc: "a visitor sees the counts and cannot react"
  attr :event, :string, default: "tayori:react"

  @doc "The reactions of an entry: each emoji with its count; the reader's own are pressed."
  def reactions(assigns) do
    {counts, mine} = assigns.reactions

    assigns =
      assigns
      |> assign(:counts, Map.get(counts, assigns.entry_id, %{}))
      |> assign(:mine, Map.get(mine, assigns.entry_id, []))

    ~H"""
    <div class="tayori-reactions" role="group" aria-label={@messages["react"]}>
      <button
        :for={emoji <- @emoji}
        type="button"
        class="tayori-reaction"
        aria-pressed={to_string(emoji in @mine)}
        disabled={@disabled}
        phx-click={@event}
        phx-value-id={@entry_id}
        phx-value-emoji={emoji}
        title={@disabled && @messages["signInToReact"]}
      >
        <span class="tayori-reaction-emoji" aria-hidden="true">{emoji}</span>
        <span :if={Map.get(@counts, emoji, 0) > 0} class="tayori-reaction-count">
          {Map.get(@counts, emoji)}
        </span>
      </button>
    </div>
    """
  end

  attr :entry_id, :string, required: true
  attr :reactions, :any, required: true

  @doc false
  # The reactions of a card, counted, not pressable: the entry has the buttons.
  def reaction_counts(assigns) do
    {counts, _mine} = assigns.reactions

    assigns =
      assign(
        assigns,
        :counts,
        counts |> Map.get(assigns.entry_id, %{}) |> Enum.sort_by(&(-elem(&1, 1))) |> Enum.take(3)
      )

    ~H"""
    <p :if={@counts != []} class="tayori-reaction-counts">
      <span :for={{emoji, n} <- @counts}>{emoji} {n}</span>
    </p>
    """
  end

  attr :tayori, :any, required: true, doc: "`@tayori`, a `Tayori.Live.State`, or nil"

  @doc """
  The entry announced to the reader now, if the app has the
  `:announcements` feature and the admin announced one: a popup, a toast
  or a banner, as the admin chose, with its button. Dismissing it is
  remembered for the reader on every device.
  """
  def announcement(%{tayori: nil} = assigns), do: ~H""
  def announcement(%{tayori: %{announcement: nil}} = assigns), do: ~H""

  # The open panel has the news: a popup or a toast would cover it.
  def announcement(%{tayori: %{open: true, announcement: %{announce: kind}}} = assigns)
      when kind != "banner",
      do: ~H""

  def announcement(assigns) do
    entry = assigns.tayori.announcement
    assigns = assign(assigns, entry: entry, t: entry.translation)

    ~H"""
    <div
      id="tayori-announcement"
      class={["tayori-announcement", "tayori-announcement-#{@entry.announce}"]}
      role={if @entry.announce == "popup", do: "dialog", else: "status"}
      aria-modal={@entry.announce == "popup" && "true"}
      aria-labelledby="tayori-announcement-title"
      lang={@t.locale}
      phx-window-keydown={@entry.announce == "popup" && "tayori:dismiss"}
      phx-key="Escape"
      phx-value-id={@entry.id}
    >
      <div class="tayori-announcement-box">
        <.cover
          :if={@entry.cover && @entry.announce != "banner"}
          cover={@entry.cover}
          class="tayori-announcement-cover"
          loading="eager"
        />
        <div class="tayori-announcement-text">
          <p class="tayori-announcement-eyebrow">
            <.icon name="sparkles" />{@tayori.messages["new"]}
          </p>
          <p id="tayori-announcement-title" class="tayori-announcement-title">{@t.title}</p>
          <p :if={@t.summary && @entry.announce != "banner"} class="tayori-announcement-summary">
            {@t.summary}
          </p>
        </div>
        <div class="tayori-announcement-actions">
          <a :if={@t.cta_url} href={@t.cta_url} class="tayori-cta">
            {@t.cta_label || @tayori.messages["tryIt"]}
          </a>
          <button
            type="button"
            class={["tayori-cta", @t.cta_url && "tayori-cta-quiet"]}
            phx-click="tayori:show"
            phx-value-id={@entry.id}
          >
            {@tayori.messages["readMore"]}
          </button>
        </div>
        <button
          type="button"
          class="tayori-icon-button tayori-announcement-close"
          phx-click="tayori:dismiss"
          phx-value-id={@entry.id}
          aria-label={@tayori.messages["dismiss"]}
        >
          <.icon name="x" />
        </button>
      </div>
      <div
        :if={@entry.announce == "popup"}
        class="tayori-announcement-backdrop"
        phx-click="tayori:dismiss"
        phx-value-id={@entry.id}
      >
      </div>
    </div>
    """
  end

  defp new?(_entry, nil), do: false
  defp new?(%Entry{published_at: nil}, _seen_before), do: false
  defp new?(%Entry{published_at: at}, seen_before), do: DateTime.compare(at, seen_before) == :gt
end
