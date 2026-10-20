defmodule Tayori.Admin.EntriesLive do
  @moduledoc false
  # The entries: drafts and scheduled first, then the published, with a
  # search and a filter of status. It follows the changes of the other
  # admins as they make them.

  use Phoenix.LiveView, layout: false

  import Tayori.Admin.Components

  alias Tayori.{Entries, Entry}

  @statuses %{"draft" => :draft, "scheduled" => :scheduled, "published" => :published}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tayori.subscribe()
    {:ok, assign(socket, page_title: "News")}
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
    entries = Entries.list(status: socket.assigns.status, search: socket.assigns.search)
    assign(socket, entries: entries, now: DateTime.utc_now())
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: list_path(socket.assigns.prefix, socket.assigns.status, q))}
  end

  @impl true
  def handle_info({Tayori, _event, _id}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <.page prefix={@prefix} page={:entries} flash={@flash}>
      <div class="ta-toolbar">
        <h1>Entries</h1>
        <.link :if={@access == :all} navigate={@prefix <> "/new"} class="ta-button ta-primary">
          New entry
        </.link>
      </div>

      <div class="ta-filters">
        <nav class="ta-tabs" aria-label="Status">
          <.link
            :for={{label, status} <- [{"All", nil}, {"Drafts", :draft}, {"Scheduled", :scheduled}, {"Published", :published}]}
            patch={list_path(@prefix, status, @search)}
            aria-current={@status == status && "page"}
          >
            {label}
          </.link>
        </nav>
        <form id="entries-search" phx-change="search" phx-submit="search" role="search">
          <input
            type="search"
            name="q"
            value={@search}
            placeholder="Search titles"
            aria-label="Search titles"
            phx-debounce="250"
            class="ta-input"
          />
        </form>
      </div>

      <ul :if={@entries != []} class="ta-entries" id="entries">
        <li :for={entry <- @entries} id={"entry-#{entry.id}"}>
          <.link navigate={@prefix <> "/" <> entry.id} class="ta-entry">
            <span class="ta-entry-title">{title(entry, @config)}</span>
            <span class="ta-entry-meta">
              <.status entry={entry} now={@now} />
              <span :for={category <- entry.categories} class="ta-chip">{category}</span>
              <span :if={entry.segments != []} class="ta-chip ta-chip-segment">
                For {Enum.join(entry.segments, ", ")}
              </span>
              <span :if={length(@config.locales) > 1} class="ta-muted">
                {entry.translations |> Enum.map(& &1.locale) |> Enum.join(" · ")}
              </span>
            </span>
          </.link>
        </li>
      </ul>

      <div :if={@entries == []} class="ta-empty">
        <p :if={@search == "" and is_nil(@status)}>
          Nothing has been written yet. The first entry tells your people what changed.
        </p>
        <p :if={@search != "" or @status}>No entries here.</p>
      </div>
    </.page>
    """
  end

  defp title(entry, config) do
    case Entry.translation(entry, nil, config.locales) do
      %{title: title} -> title
      nil -> entry.slug
    end
  end

  defp list_path(prefix, status, search) do
    query =
      [status: status && Atom.to_string(status), q: search != "" && search]
      |> Enum.filter(fn {_key, value} -> value end)

    if query == [], do: prefix, else: prefix <> "?" <> URI.encode_query(query)
  end
end
