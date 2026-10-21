defmodule Tayori.Admin.SegmentLive do
  @moduledoc false
  # A segment: its name, a line about it, and its condition in the
  # builder, with how many people are in it and the first ten as it
  # changes. Deleting it is refused while a campaign or another segment
  # names it: the page says which.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Tayori.Admin.ConditionBuilder
  alias Tayori.Campaigns.{Segment, Segments}

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: Tayori.subscribe()

    segment =
      case socket.assigns.live_action do
        :new -> %Segment{}
        :edit -> fetch!(params["id"])
      end

    {:ok,
     socket
     |> assign(
       page_title: if(segment.id, do: segment.name, else: "New segment"),
       segment: segment,
       condition: segment.condition,
       in_use: [],
       changed_elsewhere: false
     )
     |> assign_segments()
     |> assign_form(Segments.change(segment))}
  end

  defp fetch!(id) do
    Segments.get(id || "") || raise Tayori.Admin.NotFound
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: :segment))

  defp assign_segments(socket) do
    id = socket.assigns.segment.id
    segments = for s <- Segments.list(), s.id != id, do: {s.id, s.name}
    assign(socket, segments: segments)
  end

  @impl true
  def handle_event("validate", %{"segment" => params}, socket) do
    changeset =
      socket.assigns.segment
      |> Segments.change(Map.put(params, "condition", socket.assigns.condition))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"segment" => params}, %{assigns: %{access: :all}} = socket) do
    params = Map.put(params, "condition", socket.assigns.condition || %{"all" => []})

    result =
      case socket.assigns.segment do
        %Segment{id: nil} -> Segments.create(params)
        segment -> Segments.update(segment, params)
      end

    case result do
      {:ok, segment} ->
        socket = put_flash(socket, :info, "“#{segment.name}” is saved.")

        if socket.assigns.live_action == :new do
          {:noreply, push_navigate(socket, to: ~m"/audience/#{segment.id}")}
        else
          {:noreply,
           socket
           |> assign(segment: segment, condition: segment.condition, page_title: segment.name)
           |> assign_form(Segments.change(segment))}
        end

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "The segment was not saved: see the fields below.")
         |> assign_form(Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event(
        "delete",
        _params,
        %{assigns: %{access: :all, segment: %Segment{id: id}}} = socket
      )
      when is_binary(id) do
    case Segments.delete(socket.assigns.segment) do
      {:ok, _segment} ->
        {:noreply,
         socket |> put_flash(:info, "The segment is deleted.") |> push_navigate(to: ~m"/audience")}

      {:error, {:in_use, names}} ->
        {:noreply, assign(socket, in_use: names)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "The segment could not be deleted.")}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({ConditionBuilder, "segment-condition", condition}, socket) do
    {:noreply, assign(socket, condition: condition, in_use: [])}
  end

  # Another admin saved this segment: the page says so, and keeps what is
  # being written here.
  def handle_info(
        {Tayori, :segment_changed, id},
        %{assigns: %{segment: %Segment{id: id}}} = socket
      ) do
    case Segments.get(id) do
      nil -> {:noreply, assign(socket, changed_elsewhere: :deleted)}
      _segment -> {:noreply, socket |> assign(changed_elsewhere: true) |> assign_segments()}
    end
  end

  def handle_info({Tayori, :segment_changed, _id}, socket),
    do: {:noreply, assign_segments(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, read_only: assigns.access != :all)

    ~H"""
    <.page page={:audience} flash={@flash} access={@access} inbox={@inbox_new}>
      <div class="ta-heading ta-editor-heading">
        <div class="ta-heading-title">
          <.link navigate={~m"/audience"} class="ta-icon-button" aria-label="Audience">
            <.icon name="arrow-left" />
          </.link>
          <h1>{if @segment.id, do: @segment.name, else: "New segment"}</h1>
        </div>
      </div>

      <div :if={@changed_elsewhere} class="ta-notice ta-warning" role="status">
        <.icon name="info" />
        <p :if={@changed_elsewhere == true}>
          Another admin saved this segment. Saving here writes over their change;
          <.link navigate={~m"/audience/#{@segment.id}"}>open it again</.link>
          to see theirs.
        </p>
        <p :if={@changed_elsewhere == :deleted}>Another admin deleted this segment.</p>
      </div>

      <.form for={@form} id="segment-form" phx-change="validate" phx-submit="save" class="ta-card">
        <fieldset disabled={@read_only}>
          <.input field={@form[:name]} label="Name" maxlength="160" placeholder="Pro, in their first month" />
          <.input
            field={@form[:description]}
            type="textarea"
            rows="2"
            label="Description"
            maxlength="2000"
            hint="Optional: who they are, and why you write to them."
          />
        </fieldset>
      </.form>

      <section class="ta-card" aria-label="Who is in it">
        <.live_component
          module={ConditionBuilder}
          id="segment-condition"
          label="Who is in it"
          hint="The people who match these rules now. A segment is read when a letter goes, so its people change with your app."
          condition={@condition}
          count={:sample}
          segments={@segments}
          segment_id={@segment.id}
          read_only={@read_only}
        />
      </section>

      <div :if={@in_use != []} class="ta-notice" role="alert" id="segment-in-use">
        <.icon name="triangle-alert" />
        <p>
          The segment is not deleted: {Enum.join(@in_use, ", ")}
          {if length(@in_use) == 1, do: "uses", else: "use"} it. Take it out of
          {if length(@in_use) == 1, do: "it", else: "them"} first.
        </p>
      </div>

      <div :if={not @read_only} class="ta-actions">
        <button type="submit" form="segment-form" class="ta-button ta-primary">
          {if @segment.id, do: "Save", else: "Save segment"}
        </button>
        <.link navigate={~m"/audience"} class="ta-button ta-quiet">Cancel</.link>
        <button
          :if={@segment.id}
          type="button"
          class="ta-button ta-danger ta-quiet ta-push"
          phx-click="delete"
          data-confirm="Delete this segment? The people stay as they are in your app."
        >
          <.icon name="trash-2" />Delete segment
        </button>
      </div>
    </.page>
    """
  end
end
