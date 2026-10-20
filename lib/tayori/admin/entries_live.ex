defmodule Tayori.Admin.EntriesLive do
  @moduledoc false
  # The entries: drafts and scheduled first, then the published, with a
  # search and the statuses as tabs. Each row has its cover, categories,
  # languages and, with the features on, its views and reactions. It
  # follows the changes of the other admins as they make them.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Tayori.{Categories, Category, Config, Entries, Entry, Reactions, Resolver, Views}

  @statuses %{"draft" => :draft, "scheduled" => :scheduled, "published" => :published}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tayori.subscribe()
    # The names of the audiences, from the app's resolver.
    audiences =
      for {_group, segments} <- Resolver.segment_groups(socket.assigns.resolver),
          {key, label} <- segments,
          into: %{},
          do: {key, label}

    {:ok, assign(socket, page_title: "Entries", audiences: audiences)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status = Map.get(@statuses, params["status"])
    search = params["q"] || ""

    {:noreply,
     socket
     |> assign(status: status, search: search)
     |> load()}
  end

  defp load(socket) do
    config = socket.assigns.config
    entries = Entries.list(status: socket.assigns.status, search: socket.assigns.search)
    ids = Enum.map(entries, & &1.id)

    assign(socket,
      entries: entries,
      counts: Entries.counts(),
      categories: Categories.by_key(),
      views: if(Config.feature?(config, :analytics), do: Views.totals(ids)),
      reactions: if(Config.feature?(config, :reactions), do: Reactions.totals(ids)),
      now: DateTime.utc_now()
    )
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: list_path(socket.assigns.status, q))}
  end

  @impl true
  def handle_info({Tayori, _event, _id}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <.page page={:entries} flash={@flash} access={@access}>
      <div class="ta-heading">
        <div>
          <h1>Entries</h1>
          <p class="ta-subtitle">What your people read in the app, on the page and by email.</p>
        </div>
      </div>

      <div class="ta-list-bar">
        <nav class="ta-tabs" aria-label="Status">
          <.link
            :for={
              {label, status, count} <- [
                {"All", nil, @counts.all},
                {"Drafts", :draft, @counts.draft},
                {"Scheduled", :scheduled, @counts.scheduled},
                {"Published", :published, @counts.published}
              ]
            }
            patch={list_path(status, @search)}
            aria-current={@status == status && "page"}
          >
            {label} <span class="ta-count">{count}</span>
          </.link>
        </nav>
        <form id="entries-search" phx-change="search" phx-submit="search" role="search" class="ta-search">
          <.icon name="search" />
          <input
            type="search"
            name="q"
            value={@search}
            placeholder="Search titles"
            aria-label="Search titles"
            class="ta-input"
            phx-debounce="200"
          />
        </form>
      </div>

      <ol :if={@entries != []} class="ta-entries">
        <li :for={entry <- @entries} id={"entry-#{entry.id}"}>
          <.link navigate={~m"/#{entry.id}"} class="ta-entry-row">
            <span class="ta-thumb">
              <img :if={entry.cover} src={entry.cover["url"]} alt="" loading="lazy" />
              <.icon :if={!entry.cover} name="file-text" />
            </span>
            <span class="ta-entry-main">
              <span class="ta-entry-title">
                <.icon :if={entry.pinned_at} name="pin" class="ta-pin" />
                {title(entry, @config)}
              </span>
              <span :if={summary(entry, @config)} class="ta-entry-summary">
                {summary(entry, @config)}
              </span>
              <span class="ta-entry-meta">
                <.status entry={entry} now={@now} />
                <span
                  :for={key <- entry.categories}
                  class="tayori-category"
                  data-color={category_color(@categories, key)}
                >
                  {category_name(@categories, key, @config)}
                </span>
                <span :for={segment <- entry.segments} class="ta-tag" title={segment}>
                  <.icon name="lock" />{Map.get(@audiences, segment, segment)}
                </span>
                <span :if={entry.announce} class="ta-tag">
                  <.icon name="megaphone" />{String.capitalize(entry.announce)}
                </span>
                <span :if={length(@config.locales) > 1} class="ta-languages-used">
                  {entry.translations |> Enum.map(& &1.locale) |> Enum.join(" · ")}
                </span>
              </span>
            </span>
            <span :if={@views || @reactions} class="ta-entry-stats">
              <span :if={@views} title="Views">
                <.icon name="eye" />{get_in(@views, [entry.id, :views]) || 0}
              </span>
              <span :if={@views} title="Readers">
                <.icon name="users" />{get_in(@views, [entry.id, :readers]) || 0}
              </span>
              <span :if={@reactions} title="Reactions">
                <.icon name="smile-plus" />{Map.get(@reactions, entry.id, 0)}
              </span>
            </span>
            <.icon name="chevron-right" class="ta-row-chevron" />
          </.link>
        </li>
      </ol>

      <.empty :if={@entries == [] and @search != ""} icon="search" title="No entry matches">
        <p>Nothing has “{@search}” in its title or address.</p>
      </.empty>

      <.empty :if={@entries == [] and @search == ""} icon="newspaper" title={empty_title(@status)}>
        <p>Write what changed, and why it matters to your people.</p>
        <.link :if={@access == :all} navigate={~m"/new"} class="ta-button ta-primary">
          <.icon name="plus" />Write the first entry
        </.link>
      </.empty>
    </.page>
    """
  end

  defp empty_title(nil), do: "No entries yet"
  defp empty_title(:draft), do: "No drafts"
  defp empty_title(:scheduled), do: "Nothing scheduled"
  defp empty_title(:published), do: "Nothing published yet"

  defp title(entry, config) do
    case Entry.translation(entry, nil, config.locales) do
      %{title: title} when title not in [nil, ""] -> title
      _ -> entry.slug
    end
  end

  defp summary(entry, config) do
    case Entry.translation(entry, nil, config.locales) do
      %{summary: summary} when is_binary(summary) -> summary
      _ -> nil
    end
  end

  defp category_color(categories, key) do
    case categories[key] do
      %Category{color: color} -> color
      nil -> "gray"
    end
  end

  defp category_name(categories, key, config) do
    case categories[key] do
      %Category{} = category -> Category.name(category, nil, config.locales)
      nil -> key
    end
  end

  defp list_path(status, search) do
    query =
      [status: status && Atom.to_string(status), q: search != "" && search]
      |> Enum.filter(fn {_key, value} -> value end)

    ~m"/?#{query}"
  end
end
