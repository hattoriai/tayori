defmodule Tayori.Admin.AudienceLive do
  @moduledoc false
  # The audience of the campaigns: what the app says of its people (the
  # attributes and the events of its Tayori.Audience, read only), and the
  # saved segments, each with how many people are in it now, counted as
  # the page connects. It follows the segments as other admins change them.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Tayori.Admin.ConditionBuilder
  alias Tayori.{Audience, Conditions}
  alias Tayori.Audience.Attribute
  alias Tayori.Campaigns.Segments

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tayori.subscribe()
    audience = Audience.current()

    {:ok,
     socket
     |> assign(
       page_title: "Audience",
       audience: audience,
       attributes: Audience.attributes(audience),
       events: Audience.events(audience),
       events?: Audience.person_id(audience) != nil,
       counts: %{}
     )
     |> load()}
  end

  defp load(socket) do
    segments = Segments.list()

    socket
    |> assign(segments: segments)
    |> start_async(:counts, fn ->
      now = DateTime.utc_now()
      Map.new(segments, &{&1.id, Audience.count(&1.condition, now)})
    end)
  end

  @impl true
  def handle_async(:counts, {:ok, counts}, socket), do: {:noreply, assign(socket, counts: counts)}
  def handle_async(:counts, {:exit, _reason}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({Tayori, :segment_changed, _id}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.page page={:audience} flash={@flash} access={@access} inbox={@inbox_new}>
      <div class="ta-heading">
        <div>
          <h1>Audience</h1>
          <p class="ta-subtitle">
            Who your people are, as your app tells Tayori, and the groups the letters go to.
          </p>
        </div>
        <.link :if={@access == :all} navigate={~m"/audience/new"} class="ta-button ta-primary">
          <.icon name="plus" />New segment
        </.link>
      </div>

      <.card title="Segments" icon="users" id="segments">
        <ol :if={@segments != []} class="ta-entries ta-segments-list">
          <li :for={segment <- @segments} id={"segment-#{segment.id}"}>
            <.link navigate={~m"/audience/#{segment.id}"} class="ta-entry-row ta-segment-link">
              <span class="ta-entry-main">
                <span class="ta-entry-title">{segment.name}</span>
                <span class="ta-entry-summary">
                  {segment.description || Conditions.describe(segment.condition, @attributes) <> "."}
                </span>
              </span>
              <span class="ta-entry-stats">
                <span title="People in it now">
                  <.icon name="users" />{count_text(@counts[segment.id])}
                </span>
              </span>
              <.icon name="chevron-right" class="ta-row-chevron" />
            </.link>
          </li>
        </ol>
        <.empty :if={@segments == []} icon="users" title="No segments yet">
          <p>Name a group of your people once, “Pro”, “Signed up this week”, and write to it.</p>
          <.link :if={@access == :all} navigate={~m"/audience/new"} class="ta-button ta-primary">
            <.icon name="plus" />Make the first segment
          </.link>
        </.empty>
      </.card>

      <.card title="What your app says of its people" icon="list" id="attributes">
        <p class="ta-lead">
          The rules of a segment or a campaign test these facts. They come from
          <code>{inspect(@audience)}</code>, and run in your own database: Tayori copies no one.
        </p>
        <table :if={@attributes != []} class="ta-table">
          <thead>
            <tr><th scope="col">Name</th><th scope="col">Key</th><th scope="col">Type</th></tr>
          </thead>
          <tbody>
            <tr :for={attribute <- @attributes}>
              <th scope="row">
                {attribute.label}
                <span :if={attribute.description} class="ta-hint">{attribute.description}</span>
              </th>
              <td><code>{attribute.key}</code></td>
              <td>{type_text(attribute)}</td>
            </tr>
          </tbody>
        </table>
        <div :if={@attributes == []} class="ta-notice">
          <.icon name="info" />
          <p>
            No attributes yet: give <code>{inspect(@audience)}</code> an <code>attributes/0</code>
            to test what you know of your people, a plan, a sign-up date.
          </p>
        </div>
      </.card>

      <.card title="Events" icon="zap" id="events">
        <p class="ta-lead">
          What your people do, as your app tells Tayori with
          <code>Tayori.track(person_id, name)</code>. A sequence can start on an event, and a
          rule can test whether one happened.
        </p>
        <ul :if={@events != []} class="ta-features">
          <li :for={{name, label} <- @events}>
            <span class="ta-feature-icon"><.icon name="zap" /></span>
            <span><strong>{label}</strong><code>{name}</code></span>
          </li>
        </ul>
        <p :if={@events == []} class="ta-hint">
          No events are named in <code>events/0</code>; any name may be tracked anyway.
        </p>
        <div :if={not @events?} class="ta-notice">
          <.icon name="info" />
          <p>
            Rules on events need <code>person_id/0</code> in <code>{inspect(@audience)}</code>:
            the person's id as SQL, the one <code>recipient/1</code> gives.
          </p>
        </div>
      </.card>
    </.page>
    """
  end

  defp count_text(nil), do: "…"
  defp count_text(n), do: ConditionBuilder.delimit(n)

  @doc false
  def type_text(%Attribute{type: {:enum, values}}),
    do: "One of: " <> Enum.map_join(values, ", ", &elem(&1, 1))

  def type_text(%Attribute{type: type}) do
    case type do
      :string -> "Text"
      :integer -> "Number"
      :boolean -> "Yes or no"
      :datetime -> "Date and time"
      :date -> "Date"
    end
  end
end
