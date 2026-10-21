defmodule Tayori.Admin.CampaignsLive do
  @moduledoc false
  # The campaigns: the sequences and the broadcasts, as tabs, the newest
  # first, each with its purpose, status and numbers (two queries for the
  # list, Campaigns.counts/1); the archived ones on request. It follows the
  # changes of the other admins, and the letters as they go.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Tayori.Admin.ConditionBuilder
  alias Tayori.Campaigns
  alias Tayori.Campaigns.Campaign

  @kinds %{"sequence" => "sequence", "broadcast" => "broadcast"}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tayori.subscribe()
    {:ok, assign(socket, page_title: "Campaigns")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    kind = Map.get(@kinds, params["kind"], "sequence")
    archived = params["archived"] == "1"
    {:noreply, socket |> assign(kind: kind, archived: archived) |> load()}
  end

  defp load(socket) do
    all = Campaigns.list(archived: true)
    archived = Enum.filter(all, &(&1.status == "archived"))

    shown =
      Enum.filter(all, fn c ->
        c.kind == socket.assigns.kind and (socket.assigns.archived or c.status != "archived")
      end)

    tabs =
      all
      |> Enum.reject(&(&1.status == "archived"))
      |> Enum.frequencies_by(& &1.kind)

    assign(socket,
      campaigns: shown,
      counts: Campaigns.counts(shown),
      tabs: tabs,
      archived_count: Enum.count(archived, &(&1.kind == socket.assigns.kind))
    )
  end

  @impl true
  def handle_info({Tayori, event, _id}, socket)
      when event in [:campaign_changed, :segment_changed],
      do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.page page={:campaigns} flash={@flash} access={@access} inbox={@inbox_new}>
      <div class="ta-heading">
        <div>
          <h1>Campaigns</h1>
          <p class="ta-subtitle">Letters to each of your people, by what they did, at their own time.</p>
        </div>
        <div :if={@access == :all} class="ta-heading-actions">
          <.link navigate={~m"/campaigns/new?kind=sequence"} class="ta-button">
            <.icon name="plus" />New sequence
          </.link>
          <.link navigate={~m"/campaigns/new?kind=broadcast"} class="ta-button ta-primary">
            <.icon name="send" />New broadcast
          </.link>
        </div>
      </div>

      <div class="ta-list-bar">
        <nav class="ta-tabs" aria-label="Kind">
          <.link
            :for={{label, kind} <- [{"Sequences", "sequence"}, {"Broadcasts", "broadcast"}]}
            patch={~m"/campaigns?#{[kind: kind]}"}
            aria-current={@kind == kind && "page"}
          >
            {label} <span class="ta-count">{Map.get(@tabs, kind, 0)}</span>
          </.link>
        </nav>
        <.link
          :if={@archived_count > 0}
          patch={~m"/campaigns?#{archived_query(@kind, !@archived)}"}
          class="ta-link-button ta-list-link"
        >
          <.icon name="archive" />
          {if @archived, do: "Hide the archived", else: "Show the archived (#{@archived_count})"}
        </.link>
      </div>

      <ol :if={@campaigns != []} class="ta-entries ta-campaigns">
        <li :for={campaign <- @campaigns} id={"campaign-#{campaign.id}"}>
          <.link navigate={~m"/campaigns/#{campaign.id}"} class="ta-entry-row ta-campaign-row">
            <span class="ta-thumb">
              <.icon name={if campaign.kind == "sequence", do: "mail", else: "send"} />
            </span>
            <span class="ta-entry-main">
              <span class="ta-entry-title">{campaign.name}</span>
              <span class="ta-entry-meta">
                <.campaign_status campaign={campaign} />
                <span class="ta-tag">{purpose_label(campaign.purpose)}</span>
                <span :if={campaign.kind == "sequence"} class="ta-hint">
                  {trigger_text(campaign)}
                </span>
              </span>
            </span>
            <span class="ta-entry-stats">
              <span :if={campaign.kind == "sequence"} title="Entered">
                <.icon name="users" />{ConditionBuilder.delimit(@counts[campaign.id].entered)}
                <span class="ta-visually-hidden">entered</span>
              </span>
              <span :if={campaign.kind == "broadcast"} title="Recipients">
                <.icon name="users" />{ConditionBuilder.delimit(@counts[campaign.id].recipients)}
                <span class="ta-visually-hidden">recipients</span>
              </span>
              <span title="Sent">
                <.icon name="send" />{ConditionBuilder.delimit(@counts[campaign.id].sent)}
                <span class="ta-visually-hidden">sent</span>
              </span>
              <span :if={campaign.kind == "sequence"} title="Goal reached">
                <.icon name="circle-check" />{ConditionBuilder.delimit(@counts[campaign.id].goal)}
                <span class="ta-visually-hidden">reached the goal</span>
              </span>
            </span>
            <.icon name="chevron-right" class="ta-row-chevron" />
          </.link>
        </li>
      </ol>

      <.empty :if={@campaigns == [] and @kind == "sequence"} icon="mail" title="No sequences yet">
        <p>
          A sequence writes to each person after they do something: a welcome at sign-up,
          a hand on the second day, a nudge when they stall.
        </p>
        <.link :if={@access == :all} navigate={~m"/campaigns/new?kind=sequence"} class="ta-button ta-primary">
          <.icon name="plus" />Write the first sequence
        </.link>
      </.empty>

      <.empty :if={@campaigns == [] and @kind == "broadcast"} icon="send" title="No broadcasts yet">
        <p>A broadcast is one letter to a group of your people, now or at a time you choose.</p>
        <.link :if={@access == :all} navigate={~m"/campaigns/new?kind=broadcast"} class="ta-button ta-primary">
          <.icon name="plus" />Write the first broadcast
        </.link>
      </.empty>
    </.page>
    """
  end

  defp archived_query(kind, true), do: [kind: kind, archived: "1"]
  defp archived_query(kind, false), do: [kind: kind]

  attr :campaign, Campaign, required: true

  @doc "The status of a campaign, with its time when it has one."
  def campaign_status(assigns) do
    ~H"""
    <span class={["ta-status", "ta-status-#{status_class(@campaign.status)}"]}>
      {status_label(@campaign.status)}
      <.time :if={@campaign.status == "scheduled" and @campaign.send_at} at={@campaign.send_at} />
      <.time :if={@campaign.status == "sent" and @campaign.sent_at} at={@campaign.sent_at} />
    </span>
    """
  end

  defp status_class(status) when status in ["active", "sent", "sending"], do: "published"
  defp status_class(status) when status in ["scheduled", "paused"], do: "scheduled"
  defp status_class(_status), do: "draft"

  @doc false
  def status_label("draft"), do: "Draft"
  def status_label("active"), do: "Active"
  def status_label("paused"), do: "Paused"
  def status_label("archived"), do: "Archived"
  def status_label("scheduled"), do: "Scheduled"
  def status_label("sending"), do: "Sending"
  def status_label("sent"), do: "Sent"
  def status_label(other), do: other

  @doc false
  def purpose_label("marketing"), do: "Marketing"
  def purpose_label(_product), do: "Product"

  @doc false
  def trigger_text(%Campaign{trigger: %{"type" => "event", "event" => event}}),
    do: "Starts on “#{event_label(event)}”"

  def trigger_text(%Campaign{}), do: "Started by hand"

  defp event_label(event) do
    case Tayori.Audience.current() do
      nil -> event
      audience -> audience |> Tayori.Audience.events() |> Map.new() |> Map.get(event, event)
    end
  end
end
