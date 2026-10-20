defmodule Tayori.Admin.InboxLive do
  @moduledoc false
  # The inbox: the changes that shipped, the newest first, with their
  # states as tabs, filters by source and audience, and a search. The
  # admin picks some, or takes all that are new, and the digest drafts an
  # entry of them; a change readers need not know is put aside, and one
  # that says too little is edited in place. It follows the changes as
  # they come.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Tayori.Admin.Automation
  alias Tayori.{Categories, Category, Change, Digest, Entries, Entry, Inbox}

  @states ~w(new drafted hidden all)
  @sources ~w(changelog fragments api github app mcp)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tayori.subscribe()

    {:ok,
     assign(socket,
       page_title: "Inbox",
       selected: MapSet.new(),
       editing: nil,
       reading: false,
       sources: Automation.sources(socket.assigns.config)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    state = if params["state"] in @states, do: params["state"], else: "new"
    audience = if params["audience"] in Change.audiences(), do: params["audience"]
    source = if params["source"] not in [nil, ""], do: params["source"]

    {:noreply,
     socket
     |> assign(state: state, source: source, audience: audience, search: params["q"] || "")
     |> load()}
  end

  defp load(socket) do
    %{state: state, source: source, audience: audience, search: search} = socket.assigns

    changes =
      Inbox.list(
        state: if(state != "all", do: state),
        source: source,
        audience: audience,
        search: search
      )

    counts = Inbox.counts()
    selectable = for change <- changes, selectable?(change), into: MapSet.new(), do: change.id

    assign(socket,
      changes: changes,
      counts: Map.put(counts, "all", counts |> Map.values() |> Enum.sum()),
      pending: Inbox.pending_count(),
      categories: Categories.list(),
      by_key: Categories.by_key(),
      entries: entries(changes),
      selectable: selectable,
      selected: MapSet.intersection(socket.assigns.selected, selectable)
    )
  end

  # The entries of the drafted changes: nil when one is deleted.
  defp entries(changes) do
    changes
    |> Enum.filter(&(&1.state == "drafted" and &1.entry_id))
    |> Enum.map(& &1.entry_id)
    |> Enum.uniq()
    |> Map.new(&{&1, Entries.get(&1)})
  end

  # A digest takes the new changes for the public, and no others.
  defp selectable?(%Change{state: "new", audience: "public"}), do: true
  defp selectable?(_change), do: false

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         inbox_path(
           socket.assigns.state,
           params["source"] || socket.assigns.source,
           params["audience"] || socket.assigns.audience,
           params["q"] || socket.assigns.search
         )
     )}
  end

  def handle_event("toggle", %{"id" => id}, %{assigns: %{access: :all}} = socket) do
    selected =
      cond do
        MapSet.member?(socket.assigns.selected, id) -> MapSet.delete(socket.assigns.selected, id)
        MapSet.member?(socket.assigns.selectable, id) -> MapSet.put(socket.assigns.selected, id)
        true -> socket.assigns.selected
      end

    {:noreply, assign(socket, selected: selected)}
  end

  def handle_event("toggle_all", _params, %{assigns: %{access: :all}} = socket) do
    %{selected: selected, selectable: selectable} = socket.assigns

    {:noreply,
     assign(socket, selected: if(selected == selectable, do: MapSet.new(), else: selectable))}
  end

  def handle_event("clear", _params, socket),
    do: {:noreply, assign(socket, selected: MapSet.new())}

  def handle_event("draft", _params, %{assigns: %{access: :all}} = socket) do
    case MapSet.to_list(socket.assigns.selected) do
      [] -> {:noreply, socket}
      ids -> draft(socket, Digest.run(ids: ids))
    end
  end

  def handle_event("draft_all", _params, %{assigns: %{access: :all}} = socket) do
    draft(socket, Digest.run())
  end

  def handle_event("read", _params, %{assigns: %{access: :all}} = socket) do
    {:noreply, socket |> assign(reading: true) |> start_async(:read, &Automation.read_sources/0)}
  end

  def handle_event("highlight", %{"id" => id}, %{assigns: %{access: :all}} = socket) do
    with %Change{} = change <- Inbox.get(id) do
      {:ok, _} = Inbox.update(change, %{highlight: not change.highlight})
    end

    {:noreply, load(socket)}
  end

  def handle_event("hide", %{"id" => id}, %{assigns: %{access: :all}} = socket) do
    with %Change{} = change <- Inbox.get(id), do: {:ok, _} = Inbox.hide(change)

    {:noreply, socket |> put_flash(:info, "It is put aside: no entry takes it.") |> load()}
  end

  def handle_event("restore", %{"id" => id}, %{assigns: %{access: :all}} = socket) do
    with %Change{} = change <- Inbox.get(id), do: {:ok, _} = Inbox.restore(change)
    {:noreply, socket |> put_flash(:info, "It is new again.") |> load()}
  end

  def handle_event("edit", %{"id" => id}, %{assigns: %{access: :all}} = socket) do
    case Inbox.get(id) do
      %Change{} = change ->
        form = change |> Change.edit_changeset(%{}) |> to_form(as: :change)
        {:noreply, assign(socket, editing: change, form: form)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, editing: nil)}

  def handle_event("save", %{"change" => params}, %{assigns: %{access: :all}} = socket) do
    params = Map.take(params, ~w(title category audience highlight))

    case Inbox.update(socket.assigns.editing, params) do
      {:ok, _change} ->
        {:noreply, socket |> put_flash(:info, "Saved.") |> assign(editing: nil) |> load()}

      {:error, changeset} ->
        {:noreply,
         assign(socket, form: to_form(Map.put(changeset, :action, :update), as: :change))}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp draft(socket, {:ok, %Entry{} = entry}) do
    taken = length(Inbox.list(entry_id: entry.id))
    done = if Entry.status(entry) == :published, do: "published", else: "drafted"

    {:noreply,
     socket
     |> put_flash(:info, "An entry is #{done} from #{changes(taken)}.")
     |> push_navigate(to: ~m"/#{entry.id}")}
  end

  defp draft(socket, {:error, :nothing}) do
    {:noreply,
     socket
     |> put_flash(:error, "Nothing to draft: no new change for the public.")
     |> load()}
  end

  defp draft(socket, {:error, _changeset}) do
    {:noreply, put_flash(socket, :error, "The entry could not be made.")}
  end

  defp changes(1), do: "1 change"
  defp changes(n), do: "#{n} changes"

  @impl true
  def handle_async(:read, {:ok, results}, socket) do
    {:noreply,
     socket
     |> assign(reading: false)
     |> put_flash(:info, Automation.summary(results))
     |> load()}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(reading: false)
     |> put_flash(:error, "The sources could not be read: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({Tayori, event, _id}, socket) when event in [:inbox, :categories, :changed],
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        filtered: assigns.search != "" or assigns.source != nil or assigns.audience != nil,
        all_selected:
          assigns.selectable != MapSet.new() and assigns.selected == assigns.selectable
      )

    ~H"""
    <.page page={:inbox} flash={@flash} access={@access} inbox={@inbox_new}>
      <div class="ta-heading">
        <div>
          <h1>Inbox</h1>
          <p class="ta-subtitle">What shipped, before it is news. Pick what readers should know.</p>
        </div>
        <div :if={@access == :all} class="ta-heading-actions">
          <button
            :if={@sources != []}
            type="button"
            class="ta-button"
            phx-click="read"
            disabled={@reading}
          >
            <.icon name="refresh-cw" class={@reading && "ta-spin"} />
            {if @reading, do: "Reading…", else: "Read the sources now"}
          </button>
          <button
            :if={@pending > 0}
            type="button"
            class="ta-button ta-primary"
            phx-click="draft_all"
            data-confirm={"Draft one entry of the #{changes(@pending)} waiting for the public?"}
          >
            <.icon name="sparkles" />Draft from all new
          </button>
        </div>
      </div>

      <div class="ta-list-bar">
        <nav class="ta-tabs" aria-label="State">
          <.link
            :for={
              {label, state} <- [
                {"New", "new"},
                {"Drafted", "drafted"},
                {"Hidden", "hidden"},
                {"All", "all"}
              ]
            }
            patch={inbox_path(state, @source, @audience, @search)}
            aria-current={@state == state && "page"}
          >
            {label} <span class="ta-count">{@counts[state]}</span>
          </.link>
        </nav>
        <form id="inbox-filters" phx-change="filter" phx-submit="filter" class="ta-filters">
          <select name="source" class="ta-input" aria-label="Source">
            <option value="">Every source</option>
            <option
              :for={source <- source_options(@sources, @source)}
              value={source}
              selected={@source == source}
            >
              {source_label(source)}
            </option>
          </select>
          <select name="audience" class="ta-input" aria-label="Audience">
            <option value="">Every audience</option>
            <option value="public" selected={@audience == "public"}>Public</option>
            <option value="internal" selected={@audience == "internal"}>Internal</option>
          </select>
          <div role="search" class="ta-search">
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
          </div>
        </form>
      </div>

      <div :if={@changes != []} class="ta-entries ta-changes">
        <div :if={@access == :all and @selectable != MapSet.new()} class="ta-changes-head">
          <label class="ta-check-cell">
            <input
              type="checkbox"
              id="inbox-select-all"
              phx-click="toggle_all"
              checked={@all_selected}
              aria-label="Select all the new changes for the public"
            />
          </label>
          <span :if={@selected == MapSet.new()} class="ta-hint">
            Select the changes to make an entry of them.
          </span>
          <span :if={@selected != MapSet.new()} class="ta-selection" role="status">
            <strong>{MapSet.size(@selected)} selected</strong>
            <button type="button" class="ta-button ta-primary ta-small" phx-click="draft">
              <.icon name="file-text" />Draft an entry
            </button>
            <button type="button" class="ta-button ta-quiet ta-small" phx-click="clear">
              Clear
            </button>
          </span>
        </div>
        <ol>
          <li
            :for={change <- @changes}
            id={"change-#{change.id}"}
            class={[
              "ta-change",
              @access == :all && "ta-change-selectable",
              MapSet.member?(@selected, change.id) && "ta-selected"
            ]}
          >
            <.change_form
              :if={@editing && @editing.id == change.id}
              form={@form}
              categories={@categories}
              config={@config}
            />
            <div :if={!(@editing && @editing.id == change.id)} class="ta-change-row">
              <span :if={@access == :all} class="ta-check-cell">
                <input
                  :if={MapSet.member?(@selectable, change.id)}
                  type="checkbox"
                  phx-click="toggle"
                  phx-value-id={change.id}
                  checked={MapSet.member?(@selected, change.id)}
                  aria-label={"Select “#{change.title}”"}
                />
              </span>
              <span class="ta-entry-main">
                <span class="ta-entry-title">
                  <.icon :if={change.highlight} name="star" class="ta-star" />
                  {change.title}
                </span>
                <span :if={excerpt(change.body)} class="ta-entry-summary">
                  {excerpt(change.body)}
                </span>
                <span class="ta-entry-meta">
                  <span class="ta-source-pill" data-source={change.source}>
                    <.icon name={source_icon(change.source)} />{source_label(change.source)}
                  </span>
                  <span
                    :if={change.category}
                    class="tayori-category"
                    data-color={category_color(@by_key, change.category)}
                    title={change.kind}
                  >
                    {category_name(@by_key, change.category, @config)}
                  </span>
                  <span :if={!change.category and change.kind} class="ta-tag">{change.kind}</span>
                  <span :if={change.audience == "internal"} class="ta-tag ta-internal">
                    <.icon name="lock" />Internal
                  </span>
                  <span :if={change.version} class="ta-version">{change.version}</span>
                  <span class="ta-change-date"><.time at={change.occurred_at} /></span>
                  <.entry_link :if={change.state == "drafted"} change={change} entries={@entries} config={@config} />
                  <span :if={change.state == "hidden"} class="ta-tag">
                    <.icon name="archive" />Put aside
                  </span>
                  <a
                    :if={change.url}
                    href={change.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="ta-change-link"
                  >
                    <.icon name="external-link" />{short_url(change.url)}
                  </a>
                </span>
              </span>
              <span :if={@access == :all} class="ta-row-actions">
                <button
                  type="button"
                  class={["ta-icon-button", "ta-star-button"]}
                  phx-click="highlight"
                  phx-value-id={change.id}
                  aria-pressed={to_string(change.highlight)}
                  aria-label={"Lead with “#{change.title}”"}
                  title={if change.highlight, do: "Highlighted", else: "Highlight"}
                >
                  <.icon name="star" />
                </button>
                <button
                  type="button"
                  class="ta-icon-button"
                  phx-click="edit"
                  phx-value-id={change.id}
                  aria-label={"Edit “#{change.title}”"}
                  title="Edit"
                >
                  <.icon name="pencil" />
                </button>
                <button
                  :if={change.state == "new"}
                  type="button"
                  class="ta-icon-button"
                  phx-click="hide"
                  phx-value-id={change.id}
                  aria-label={"Put “#{change.title}” aside"}
                  title="Put aside"
                >
                  <.icon name="archive" />
                </button>
                <button
                  :if={restorable?(change, @entries)}
                  type="button"
                  class="ta-icon-button"
                  phx-click="restore"
                  phx-value-id={change.id}
                  aria-label={"Restore “#{change.title}”"}
                  title="Restore"
                >
                  <.icon name="undo-2" />
                </button>
              </span>
            </div>
          </li>
        </ol>
      </div>

      <.empty :if={@changes == [] and @filtered} icon="search" title="No change matches">
        <p :if={@search != ""}>Nothing here has “{@search}” in its title.</p>
        <p :if={@search == ""}>Nothing here comes from there, or is for them.</p>
        <.link patch={inbox_path(@state, nil, nil, "")} class="ta-button">Clear the filters</.link>
      </.empty>

      <.empty
        :if={@changes == [] and not @filtered and @counts["all"] == 0}
        icon="inbox"
        title="The inbox is empty"
      >
        <p>
          What ships comes here: your changelog and news fragments when the app starts, your CI
          over the API, GitHub's merged pull requests, and your own code.
        </p>
        <span class="ta-actions">
          <.link navigate={~m"/settings#automation"} class="ta-button">
            <.icon name="settings" />Set up the sources
          </.link>
          <a
            href="https://hexdocs.pm/tayori/automation.html"
            target="_blank"
            rel="noopener noreferrer"
            class="ta-button ta-quiet"
          >
            Read the guide<.icon name="arrow-up-right" />
          </a>
        </span>
      </.empty>

      <.empty
        :if={@changes == [] and not @filtered and @counts["all"] > 0}
        icon="inbox"
        title={empty_title(@state)}
      >
        <p>{empty_text(@state)}</p>
      </.empty>
    </.page>
    """
  end

  attr :change, Change, required: true
  attr :entries, :map, required: true
  attr :config, :any, required: true

  # The entry a drafted change is in, or that it is gone.
  defp entry_link(assigns) do
    assigns = assign(assigns, :entry, assigns.entries[assigns.change.entry_id])

    ~H"""
    <.link :if={@entry} navigate={~m"/#{@entry.id}"} class="ta-change-entry">
      <.icon name="newspaper" />In “{entry_title(@entry, @config)}”
    </.link>
    <span :if={!@entry} class="ta-tag"><.icon name="newspaper" />Its entry is deleted</span>
    """
  end

  attr :form, :any, required: true
  attr :categories, :list, required: true
  attr :config, :any, required: true

  defp change_form(assigns) do
    ~H"""
    <.form for={@form} id="change-form" class="ta-change-form" phx-submit="save">
      <.input field={@form[:title]} label="Title" maxlength="255" autocomplete="off" />
      <div class="ta-change-form-row">
        <div class="ta-field">
          <label for="change_category">Category</label>
          <select id="change_category" name="change[category]" class="ta-input">
            <option value="">None</option>
            <option
              :for={category <- @categories}
              value={category.key}
              selected={@form[:category].value == category.key}
            >
              {Category.name(category, nil, @config.locales)}
            </option>
          </select>
        </div>
        <div class="ta-field">
          <label for="change_audience">Audience</label>
          <select id="change_audience" name="change[audience]" class="ta-input">
            <option value="public" selected={@form[:audience].value == "public"}>
              Public: it can go in an entry
            </option>
            <option value="internal" selected={@form[:audience].value == "internal"}>
              Internal: for the team only
            </option>
          </select>
        </div>
        <label class="ta-check">
          <input type="hidden" name="change[highlight]" value="false" />
          <input
            type="checkbox"
            name="change[highlight]"
            value="true"
            checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:highlight].value)}
          /> Lead with it
        </label>
      </div>
      <div class="ta-actions">
        <button type="submit" class="ta-button ta-primary">Save</button>
        <button type="button" class="ta-button ta-quiet" phx-click="cancel">Cancel</button>
      </div>
    </.form>
    """
  end

  defp restorable?(%Change{state: "hidden"}, _entries), do: true

  defp restorable?(%Change{state: "drafted", entry_id: id}, entries),
    do: Map.get(entries, id) == nil

  defp restorable?(_change, _entries), do: false

  defp empty_title("new"), do: "Nothing new"
  defp empty_title("drafted"), do: "Nothing drafted yet"
  defp empty_title("hidden"), do: "Nothing put aside"
  defp empty_title(_all), do: "The inbox is empty"

  defp empty_text("new"), do: "Every change is in an entry, or put aside."
  defp empty_text("drafted"), do: "The changes in an entry are kept here, with a link to it."
  defp empty_text("hidden"), do: "What readers need not know waits here, out of every entry."
  defp empty_text(_all), do: "What ships comes here."

  # The known sources, the app's own, and the one filtered by.
  defp source_options(sources, current) do
    (@sources ++ Enum.map(sources, & &1.name) ++ List.wrap(current)) |> Enum.uniq()
  end

  @doc false
  def source_label("changelog"), do: "Changelog"
  def source_label("fragments"), do: "Fragments"
  def source_label("api"), do: "API"
  def source_label("github"), do: "GitHub"
  def source_label("app"), do: "App"
  def source_label("mcp"), do: "MCP"
  def source_label(other), do: other

  @doc false
  def source_icon("changelog"), do: "file-text"
  def source_icon("fragments"), do: "layers"
  def source_icon("api"), do: "code-xml"
  def source_icon("github"), do: "git-pull-request"
  def source_icon("app"), do: "app-window"
  def source_icon("mcp"), do: "sparkles"
  def source_icon(_other), do: "inbox"

  # The start of the body, as text.
  defp excerpt(nil), do: nil

  defp excerpt(body) do
    text =
      body
      |> String.replace(~r/!?\[([^\]]*)\]\([^)]*\)/, "\\1")
      |> String.replace(~r/[#*_`>~|]+/, "")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    if text == "", do: nil, else: String.slice(text, 0, 240)
  end

  @doc false
  # An address without its scheme, short enough for a row.
  def short_url(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when is_binary(host) ->
        text = String.replace_prefix(host, "www.", "") <> String.trim_trailing(path || "", "/")
        if String.length(text) > 48, do: String.slice(text, 0, 47) <> "…", else: text

      _ ->
        url
    end
  end

  defp entry_title(entry, config) do
    case Entry.translation(entry, nil, config.locales) do
      %{title: title} when title not in [nil, ""] -> title
      _ -> entry.slug
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

  defp inbox_path(state, source, audience, search) do
    query =
      [
        state: state != "new" && state,
        source: source not in [nil, ""] && source,
        audience: audience not in [nil, ""] && audience,
        q: search not in [nil, ""] && search
      ]
      |> Enum.filter(fn {_key, value} -> value end)

    ~m"/inbox?#{query}"
  end
end
