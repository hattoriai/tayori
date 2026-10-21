defmodule Tayori.Admin.CampaignLive do
  @moduledoc false
  # Writes a campaign. Its settings: name, purpose, sender; for a
  # sequence, what starts it, who may enter, its goal, the gap between two
  # letters and how long a person stays; for a broadcast, who gets it.
  # Then its letters: a sequence's steps, top to bottom, each when it goes,
  # when it is skipped, and its letter in each language (the body in
  # Kotoba's editor, with images), one step open at a time; a broadcast's
  # one letter. The side has its status and what can be done now (start,
  # pause, resume, archive; schedule, send now, cancel, after a word that
  # says how many people it reaches), and its results. The preview shows
  # a saved letter as a person of the audience gets it, and sends a test.
  #
  # It follows the changes of the other admins, and the letters as they go.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS
  alias Tayori.Admin.{CampaignsLive, ConditionBuilder}
  alias Tayori.{Audience, Campaigns, Config, Recipient, Resolver}
  alias Tayori.Campaigns.{Campaign, Letter, Letters, Segments, Step}

  @compile {:no_warn_undefined, [Tayori.Campaigns.Letters]}

  @accept ~w(.png .jpg .jpeg .gif .webp)
  @max_file_size 25_000_000
  @kinds ["sequence", "broadcast"]

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: Tayori.subscribe()

    campaign =
      case socket.assigns.live_action do
        :new ->
          kind = if params["kind"] in @kinds, do: params["kind"], else: "sequence"
          %Campaign{kind: kind, steps: []}

        :edit ->
          fetch!(params["id"])
      end

    locales = socket.assigns.config.locales
    author = Resolver.author(socket.assigns.resolver, socket.assigns.user) || %{}

    socket =
      socket
      |> assign(
        campaign: campaign,
        page_title: title(campaign),
        mode: :write,
        open: nil,
        step: nil,
        step_form: nil,
        language: hd(locales),
        conditions: %{"audience" => campaign.audience, "goal" => campaign.goal},
        skip: nil,
        confirm: nil,
        preview: nil,
        test_address: author["email"] || "",
        enroll_segment: "",
        changed_elsewhere: false
      )
      |> assign_settings(Campaigns.change(campaign))
      |> assign_segments()
      |> assign(:schedule, to_form(%{"at" => campaign.send_at}, as: :schedule))
      |> assign_results()
      |> allow_uploads(locales)

    socket =
      if campaign.kind == "broadcast" and campaign.id,
        do: open_step(socket, hd(campaign.steps)),
        else: socket

    {:ok, socket}
  end

  defp fetch!(id), do: Campaigns.get(id || "") || raise(Tayori.Admin.NotFound)

  defp title(%Campaign{id: nil, kind: "broadcast"}), do: "New broadcast"
  defp title(%Campaign{id: nil}), do: "New sequence"
  defp title(%Campaign{name: name}), do: name

  defp assign_settings(socket, changeset),
    do: assign(socket, :settings, to_form(changeset, as: :campaign))

  defp assign_segments(socket) do
    assign(socket, :segments, Enum.map(Segments.list(), &{&1.id, &1.name}))
  end

  defp assign_results(%{assigns: %{campaign: %Campaign{id: nil}}} = socket),
    do: assign(socket, :results, nil)

  defp assign_results(socket),
    do: assign(socket, :results, Campaigns.results(socket.assigns.campaign))

  # One upload for each language, for the step that is open: Kotoba puts
  # each file in the editor it was dropped on. Only an admin who may write
  # uploads.
  defp allow_uploads(%{assigns: %{access: access}} = socket, _locales) when access != :all,
    do: socket

  defp allow_uploads(socket, locales) do
    Enum.reduce(locales, socket, fn locale, socket ->
      allow_upload(socket, upload_name(locales, locale),
        accept: @accept,
        max_file_size: @max_file_size,
        max_entries: 10,
        auto_upload: true,
        progress: &handle_progress/3
      )
    end)
  end

  # The upload names are made from the configured languages, never from a
  # request: a short, known list of atoms.
  defp upload_name(locales, locale) do
    index = Enum.find_index(locales, &(&1 == locale))
    :"tayori_letter_#{index}"
  end

  defp editor_id(open, locale), do: "tayori-letter-#{open}-#{locale}"

  def handle_progress(name, upload, socket) do
    locales = socket.assigns.config.locales
    locale = Enum.find(locales, &(upload_name(locales, &1) == name))

    if upload.done? and locale,
      do: {:noreply, consume(socket, locale)},
      else: {:noreply, socket}
  end

  defp consume_all(%{assigns: %{access: :all, open: open}} = socket) when open != nil do
    Enum.reduce(socket.assigns.config.locales, socket, &consume(&2, &1))
  end

  defp consume_all(socket), do: socket

  defp consume(%{assigns: %{open: nil}} = socket, _locale), do: socket

  defp consume(socket, locale) do
    opts = if socket.assigns.storage, do: [storage: socket.assigns.storage], else: []

    Kotoba.Live.consume_uploads(
      socket,
      upload_name(socket.assigns.config.locales, locale),
      editor_id(socket.assigns.open, locale),
      opts
    )
  end

  # ── The settings ────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"campaign" => params}, socket) do
    changeset =
      socket.assigns.campaign
      |> Campaigns.change(settings_attrs(socket, params))
      |> Map.put(:action, :validate)

    {:noreply, assign_settings(socket, changeset)}
  end

  def handle_event("save", %{"campaign" => params}, %{assigns: %{access: :all}} = socket) do
    attrs = settings_attrs(socket, params)
    %{campaign: campaign, resolver: resolver, user: user} = socket.assigns

    result =
      case campaign do
        %Campaign{id: nil, kind: kind} ->
          Campaigns.create(Map.put(attrs, "kind", kind), author: Resolver.author(resolver, user))

        campaign ->
          Campaigns.update(campaign, attrs)
      end

    case result do
      {:ok, saved} when campaign.id == nil ->
        {:noreply,
         socket
         |> put_flash(:info, "The #{saved.kind} is saved. Now write its letter.")
         |> push_navigate(to: ~m"/campaigns/#{saved.id}")}

      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved.")
         |> assign(campaign: saved, page_title: saved.name, changed_elsewhere: false)
         |> assign_settings(Campaigns.change(saved))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "The campaign was not saved: see the fields below.")
         |> assign_settings(Map.put(changeset, :action, :insert))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason, socket.assigns.campaign))}
    end
  end

  # ── The steps ───────────────────────────────────────────────────

  def handle_event("open_step", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.campaign.steps, &(&1.id == id)) do
      nil -> {:noreply, socket}
      step -> {:noreply, open_step(socket, step)}
    end
  end

  def handle_event("new_step", _params, %{assigns: %{access: :all}} = socket) do
    %{campaign: campaign, config: config} = socket.assigns

    if (campaign.id && campaign.kind == "sequence") and not locked?(campaign) do
      wait =
        case List.last(campaign.steps) do
          nil -> 0
          step -> step.wait + 1440
        end

      step = %Step{
        campaign_id: campaign.id,
        wait: wait,
        letters: [%Letter{locale: Config.default_locale(config)}]
      }

      {:noreply, open_step(socket, step)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_step", _params, socket) do
    {:noreply, assign(socket, open: nil, step_form: nil)}
  end

  def handle_event("language", %{"locale" => locale}, socket) do
    if locale in socket.assigns.config.locales,
      do: {:noreply, assign(socket, :language, locale)},
      else: {:noreply, socket}
  end

  def handle_event("add_language", %{"locale" => locale}, %{assigns: %{access: :all}} = socket) do
    if socket.assigns.open && locale in socket.assigns.config.locales do
      changeset = socket.assigns.step_form.source
      letters = Ecto.Changeset.get_assoc(changeset, :letters)

      changeset =
        Ecto.Changeset.put_assoc(changeset, :letters, letters ++ [%Letter{locale: locale}])

      {:noreply, socket |> assign_step(changeset) |> assign(:language, locale)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_step", %{"step" => params}, %{assigns: %{open: open}} = socket)
      when open != nil do
    socket = consume_all(socket)

    changeset =
      socket.assigns.step
      |> step_changeset(step_attrs(socket, params))
      |> Map.put(:action, :validate)

    {:noreply, assign_step(socket, changeset)}
  end

  def handle_event(
        "save_step",
        %{"step" => params},
        %{assigns: %{access: :all, open: open}} = socket
      )
      when open != nil do
    socket = consume_all(socket)
    %{campaign: campaign, step: step} = socket.assigns
    attrs = step_attrs(socket, params)

    result =
      case open do
        "new" -> Campaigns.add_step(campaign, attrs)
        _id -> Campaigns.update_step(step, attrs)
      end

    case result do
      {:ok, saved} ->
        campaign = Campaigns.get(campaign.id)
        saved = Enum.find(campaign.steps, &(&1.id == saved.id))

        {:noreply,
         socket
         |> put_flash(
           :info,
           if(campaign.kind == "broadcast",
             do: "The letter is saved.",
             else: "The step is saved."
           )
         )
         |> assign(campaign: campaign)
         |> assign_results()
         |> open_step(saved)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Not saved: see the fields below.")
         |> assign_step(Map.put(changeset, :action, :insert))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason, campaign))}
    end
  end

  def handle_event("move_step", %{"id" => id, "to" => to}, %{assigns: %{access: :all}} = socket)
      when to in ["up", "down"] do
    with %Step{} = step <- Enum.find(socket.assigns.campaign.steps, &(&1.id == id)),
         {:ok, _step} <- Campaigns.move_step(step, String.to_existing_atom(to)) do
      {:noreply, reload(socket)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason, socket.assigns.campaign))}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_step", %{"id" => id}, %{assigns: %{access: :all}} = socket) do
    with %Step{} = step <- Enum.find(socket.assigns.campaign.steps, &(&1.id == id)),
         {:ok, _step} <- Campaigns.remove_step(step) do
      socket =
        if socket.assigns.open == id, do: assign(socket, open: nil, step_form: nil), else: socket

      {:noreply, socket |> put_flash(:info, "The step is deleted.") |> reload()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason, socket.assigns.campaign))}

      nil ->
        {:noreply, socket}
    end
  end

  # ── Its life ────────────────────────────────────────────────────

  def handle_event("status", %{"to" => to}, %{assigns: %{access: :all}} = socket)
      when to in ["start", "pause", "resume", "archive"] do
    campaign = socket.assigns.campaign

    result =
      case to do
        "start" -> Campaigns.start(campaign)
        "pause" -> Campaigns.pause(campaign)
        "resume" -> Campaigns.resume(campaign)
        "archive" -> Campaigns.archive(campaign)
      end

    case result do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, status_message(to, campaign))
         |> assign(campaign: campaign, confirm: nil)
         |> assign_results()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason, campaign))}
    end
  end

  def handle_event(
        "delete",
        _params,
        %{assigns: %{access: :all, campaign: %Campaign{id: id}}} = socket
      )
      when is_binary(id) do
    case Campaigns.delete(socket.assigns.campaign) do
      {:ok, _campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, "The campaign is deleted.")
         |> push_navigate(to: ~m"/campaigns?#{[kind: socket.assigns.campaign.kind]}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason, socket.assigns.campaign))}
    end
  end

  def handle_event("schedule_change", %{"schedule" => params}, socket) do
    {:noreply, assign(socket, schedule: to_form(params, as: :schedule))}
  end

  def handle_event("schedule", %{"schedule" => params}, %{assigns: %{access: :all}} = socket) do
    socket = assign(socket, schedule: to_form(params, as: :schedule))
    now = DateTime.utc_now()

    case parse_time(params["at"]) do
      %DateTime{} = at ->
        if DateTime.compare(at, now) == :gt,
          do: {:noreply, ask(socket, {:schedule, at})},
          else:
            {:noreply,
             put_flash(
               socket,
               :error,
               "That time has passed: choose a later one, or send it now."
             )}

      nil ->
        {:noreply, put_flash(socket, :error, "Choose a day and a time, or send it now.")}
    end
  end

  def handle_event("send_now", _params, %{assigns: %{access: :all}} = socket) do
    {:noreply, ask(socket, :send_now)}
  end

  def handle_event("enroll", %{"segment" => segment}, %{assigns: %{access: :all}} = socket) do
    {:noreply, socket |> assign(enroll_segment: segment) |> ask({:enroll, segment})}
  end

  def handle_event("not_now", _params, socket), do: {:noreply, assign(socket, confirm: nil)}

  def handle_event(
        "confirm",
        _params,
        %{assigns: %{access: :all, confirm: %{action: action}}} = socket
      ) do
    campaign = socket.assigns.campaign

    result =
      case action do
        :send_now -> Campaigns.send_broadcast_now(campaign)
        {:schedule, at} -> Campaigns.schedule_broadcast(campaign, at)
        {:enroll, segment} -> Campaigns.enroll_segment(campaign, segment_or_everyone(segment))
      end

    case result do
      {:ok, n} when is_integer(n) ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{ConditionBuilder.people(n) |> String.capitalize()} entered the sequence."
         )
         |> assign(confirm: nil)
         |> reload()}

      {:ok, campaign} ->
        message =
          if match?({:schedule, _}, action),
            do: "The broadcast is scheduled.",
            else: "The broadcast is on its way."

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(campaign: campaign, confirm: nil)
         |> assign_results()}

      {:error, reason} ->
        {:noreply,
         socket |> assign(confirm: nil) |> put_flash(:error, error_text(reason, campaign))}
    end
  end

  def handle_event("cancel_schedule", _params, %{assigns: %{access: :all}} = socket) do
    case Campaigns.cancel_broadcast(socket.assigns.campaign) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, "The broadcast is a draft again: it does not go.")
         |> assign(campaign: campaign, schedule: to_form(%{"at" => nil}, as: :schedule))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason, socket.assigns.campaign))}
    end
  end

  # ── The preview ─────────────────────────────────────────────────

  def handle_event("mode", %{"mode" => mode}, %{assigns: %{campaign: %Campaign{id: id}}} = socket)
      when mode in ["write", "preview"] and is_binary(id) do
    socket = assign(socket, :mode, String.to_existing_atom(mode))
    {:noreply, if(mode == "preview", do: start_preview(socket), else: socket)}
  end

  def handle_event("preview", params, %{assigns: %{preview: %{}}} = socket) do
    preview = socket.assigns.preview
    step_id = params["step"] || preview.step_id

    person =
      case String.trim(params["person_id"] || "") do
        "" -> params["person"] || preview.person
        id -> id
      end

    {:noreply,
     assign(socket,
       preview:
         render_preview(socket.assigns.campaign, %{
           preview
           | step_id: step_id,
             person: person,
             typed: params["person_id"] || ""
         })
     )}
  end

  def handle_event(
        "test",
        %{"address" => address},
        %{assigns: %{access: :all, preview: %{} = preview}} = socket
      ) do
    address = String.trim(address)
    socket = assign(socket, test_address: address)

    with true <-
           address =~ ~r/\A[^\s@]+@[^\s@]+\z/ || {:error, "Write an address to send the test to."},
         %Step{} = step <-
           preview_step(socket.assigns.campaign, preview.step_id) || {:error, "Choose a step."},
         true <- step.letters != [] || {:error, "This step has no letter yet."},
         {:ok, _meta} <-
           Letters.send_test(socket.assigns.campaign, step, preview.recipient, address) do
      {:noreply, put_flash(socket, :info, "A test went to #{address}.")}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "The test was not sent: #{inspect(reason)}.")}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # ── Messages ────────────────────────────────────────────────────

  @impl true
  def handle_info({ConditionBuilder, "skip-" <> _open, condition}, socket) do
    {:noreply, assign(socket, :skip, condition)}
  end

  def handle_info({ConditionBuilder, field, condition}, socket)
      when field in ["audience", "goal"] do
    {:noreply, update(socket, :conditions, &Map.put(&1, field, condition))}
  end

  def handle_info(
        {Tayori, :campaign_changed, id},
        %{assigns: %{campaign: %Campaign{id: id}}} = socket
      ) do
    case Campaigns.get(id) do
      nil -> {:noreply, assign(socket, changed_elsewhere: :deleted)}
      _campaign -> {:noreply, reload(socket)}
    end
  end

  def handle_info({Tayori, :segment_changed, _id}, socket),
    do: {:noreply, assign_segments(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # The campaign as it is now, the forms as they are: a step deleted
  # elsewhere closes.
  defp reload(socket) do
    campaign = Campaigns.get(socket.assigns.campaign.id)
    open = socket.assigns.open

    socket =
      if open not in [nil, "new"] and not Enum.any?(campaign.steps, &(&1.id == open)),
        do: assign(socket, open: nil, step_form: nil),
        else: socket

    socket = assign(socket, campaign: campaign, page_title: campaign.name) |> assign_results()

    if socket.assigns.preview,
      do: assign(socket, preview: render_preview(campaign, socket.assigns.preview)),
      else: socket
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp open_step(socket, %Step{} = step) do
    socket
    |> assign(
      open: step.id || "new",
      step: step,
      skip: step.skip_if,
      language: hd(socket.assigns.config.locales)
    )
    |> assign_step(step_changeset(step, %{}))
  end

  defp assign_step(socket, changeset),
    do: assign(socket, :step_form, to_form(changeset, as: :step))

  defp step_changeset(step, attrs) do
    config = Config.get()
    Step.changeset(step, attrs, Audience.attributes(Audience.current()), config.locales)
  end

  # The step's form: its wait in days and hours, its skip from the
  # builder, its letters less those the admin removed.
  defp step_attrs(socket, params) do
    drop = List.wrap(params["letters_drop"])

    letters =
      (params["letters"] || %{})
      |> Enum.reject(fn {index, _letter} -> index in drop end)
      |> Enum.sort_by(fn {index, _letter} -> String.to_integer(index) end)
      |> Enum.map(fn {_index, letter} -> letter end)

    attrs = %{"letters" => letters}

    if socket.assigns.campaign.kind == "sequence" do
      Map.merge(attrs, %{
        "wait" => wait(params),
        "skip_if" => condition_or_nil(socket.assigns.skip)
      })
    else
      attrs
    end
  end

  defp wait(params) do
    parts = [{params["wait_days"], 1440}, {params["wait_hours"], 60}, {params["wait_minutes"], 1}]

    Enum.reduce_while(parts, 0, fn {value, unit}, acc ->
      case Integer.parse(String.trim(value || "")) do
        {n, ""} -> {:cont, acc + n * unit}
        :error when value in [nil, ""] -> {:cont, acc}
        _ -> {:halt, "invalid"}
      end
    end)
  end

  defp settings_attrs(socket, params) do
    kind = socket.assigns.campaign.kind
    conditions = socket.assigns.conditions
    attrs = Map.take(params, ~w(name purpose from_name reply_to))

    case kind do
      "sequence" ->
        trigger =
          case params["trigger_type"] do
            "event" -> %{"type" => "event", "event" => params["trigger_event"] || ""}
            _manual -> %{"type" => "manual"}
          end

        Map.merge(attrs, %{
          "trigger" => trigger,
          "min_gap_hours" => params["min_gap_hours"],
          "max_days" => blank_to_nil(params["max_days"]),
          "audience" => condition_or_nil(conditions["audience"]),
          "goal" => condition_or_nil(conditions["goal"])
        })

      "broadcast" ->
        Map.put(attrs, "audience", condition_or_nil(conditions["audience"]))
    end
  end

  defp condition_or_nil(%{"all" => []}), do: nil
  defp condition_or_nil(condition), do: condition

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp parse_time(at) when is_binary(at) and at != "" do
    case DateTime.from_iso8601(at) do
      {:ok, at, _offset} -> at
      {:error, _} -> nil
    end
  end

  defp parse_time(_at), do: nil

  # A word before it goes: how many people it reaches, counted now.
  defp ask(socket, action) do
    campaign = socket.assigns.campaign

    condition =
      case action do
        {:enroll, segment} -> both(campaign.audience, segment_condition(segment))
        _broadcast -> campaign.audience
      end

    assign(socket, confirm: %{action: action, count: Audience.count(condition)})
  end

  defp segment_condition(""), do: nil
  defp segment_condition(id), do: %{"segment" => id, "op" => "in"}

  defp segment_or_everyone(""), do: nil
  defp segment_or_everyone(id), do: id

  defp both(nil, nil), do: nil
  defp both(nil, condition), do: condition
  defp both(audience, nil), do: audience
  defp both(audience, condition), do: %{"all" => [audience, condition]}

  defp start_preview(socket) do
    campaign = socket.assigns.campaign
    people = Audience.sample(campaign.audience, 10)

    step_id =
      case {socket.assigns.open, campaign.steps} do
        {open, _steps} when open not in [nil, "new"] -> open
        {_open, [step | _]} -> step.id
        {_open, []} -> nil
      end

    preview = %{
      step_id: step_id,
      people: people,
      person: people |> List.first() |> then(&(&1 && &1.id)),
      typed: "",
      recipient: nil,
      email: nil,
      missing: [],
      problem: nil
    }

    assign(socket, preview: render_preview(campaign, preview))
  end

  # The step's saved letter, to a person: the email as they get it.
  defp render_preview(campaign, preview) do
    recipient =
      Enum.find(preview.people, &(&1.id == preview.person)) ||
        (preview.person && Audience.get(preview.person)) ||
        %Recipient{id: "preview"}

    preview = %{preview | recipient: recipient, email: nil, missing: [], problem: nil}

    if preview.person not in [nil, ""] and recipient.id == "preview",
      do: %{preview | problem: "No one in your app has the id “#{preview.person}”."},
      else: render_letter(campaign, preview, recipient)
  end

  defp render_letter(campaign, preview, recipient) do
    case preview_step(campaign, preview.step_id) do
      nil ->
        %{preview | problem: "Write a step first."}

      %Step{letters: []} ->
        %{preview | problem: "This step has no letter yet."}

      step ->
        email =
          Letters.render(campaign, step, recipient, to: recipient.email || "preview@example.com")

        %{preview | email: email, missing: Letters.missing(campaign, recipient)}
    end
  end

  defp preview_step(campaign, id), do: Enum.find(campaign.steps, &(&1.id == id))

  defp locked?(%Campaign{status: "archived"}), do: true

  defp locked?(%Campaign{kind: "broadcast", status: status}) when status in ["sending", "sent"],
    do: true

  defp locked?(%Campaign{}), do: false

  defp status_message("start", _campaign),
    do: "The sequence is started: it takes people in from now."

  defp status_message("pause", _campaign),
    do: "The sequence is paused: no one enters, and no letter goes."

  defp status_message("resume", _campaign), do: "The sequence goes on, where each person was."
  defp status_message("archive", _campaign), do: "The campaign is archived."

  @doc false
  # The context's refusals, as sentences.
  def error_text(:locked, %Campaign{status: "archived"}),
    do: "An archived campaign does not change."

  def error_text(:locked, %Campaign{}), do: "This broadcast is sent: its letter stays as it went."
  def error_text(:one_step, _campaign), do: "A broadcast has one letter."
  def error_text(:no_steps, _campaign), do: "A sequence needs a step to start: add one."

  def error_text({:incomplete, ids}, %Campaign{} = campaign) do
    locale = Tayori.Locales.name(Config.default_locale(Config.get()))

    case campaign.kind do
      "broadcast" ->
        "The letter needs a subject and a body in #{locale} first."

      _sequence ->
        numbers =
          for {step, n} <- Enum.with_index(campaign.steps, 1), step.id in ids, do: "step #{n}"

        "Each step needs a letter in #{locale} with a subject and a body: " <>
          Enum.join(numbers, ", ") <>
          " " <> if(length(numbers) == 1, do: "has not.", else: "have not.")
    end
  end

  def error_text(:sending, _campaign), do: "The broadcast is being sent: it cannot change now."

  def error_text(:not_draft, _campaign),
    do: "Only a draft or an archived campaign is deleted. Archive it first."

  def error_text(:not_active, _campaign), do: "Only an active sequence takes people in."
  def error_text(:not_found, _campaign), do: "That segment no longer exists."

  def error_text({:status, status}, _campaign),
    do: "It is #{String.downcase(CampaignsLive.status_label(status))}: that cannot be done now."

  def error_text(_reason, _campaign), do: "That could not be done."

  # ── Rendering ───────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        read_only: assigns.access != :all,
        locked: locked?(assigns.campaign),
        sequence: assigns.campaign.kind == "sequence"
      )

    ~H"""
    <.page page={:campaigns} flash={@flash} access={@access} inbox={@inbox_new} wide>
      <div class="ta-heading ta-editor-heading">
        <div class="ta-heading-title">
          <.link navigate={~m"/campaigns?#{[kind: @campaign.kind]}"} class="ta-icon-button" aria-label="Campaigns">
            <.icon name="arrow-left" />
          </.link>
          <h1>{title(@campaign)}</h1>
          <CampaignsLive.campaign_status :if={@campaign.id} campaign={@campaign} />
        </div>
        <div :if={@campaign.id} class="ta-heading-actions">
          <div class="ta-segmented" role="tablist" aria-label="Write or preview">
            <button
              type="button"
              role="tab"
              aria-selected={to_string(@mode == :write)}
              phx-click="mode"
              phx-value-mode="write"
            >
              <.icon name="pencil" />Write
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={to_string(@mode == :preview)}
              phx-click="mode"
              phx-value-mode="preview"
            >
              <.icon name="eye" />Preview
            </button>
          </div>
        </div>
      </div>

      <div :if={@changed_elsewhere == :deleted} class="ta-notice ta-warning" role="status">
        <.icon name="info" />
        <p>Another admin deleted this campaign.</p>
      </div>

      <div class="ta-editor ta-campaign">
        <div class="ta-campaign-main">
          <.preview_card
            :if={@mode == :preview and @preview}
            preview={@preview}
            campaign={@campaign}
            read_only={@read_only}
            test_address={@test_address}
          />

          <div hidden={@mode == :preview}>
            <.settings_card
              settings={@settings}
              campaign={@campaign}
              conditions={@conditions}
              segments={@segments}
              read_only={@read_only or @locked}
              config={@config}
            />

            <section :if={@campaign.id && @sequence} class="ta-steps-section" aria-labelledby="steps-title">
              <div class="ta-subheading-row">
                <h2 id="steps-title" class="ta-section-title">Steps</h2>
                <p class="ta-hint">
                  Each letter goes at its time after the person entered, unless its skip matches them then.
                </p>
              </div>
              <ol :if={@campaign.steps != [] or @open == "new"} class="ta-letter-steps">
                <li :for={{step, n} <- Enum.with_index(@campaign.steps, 1)} id={"step-#{step.id}"}>
                  <.step_editor
                    :if={@open == step.id}
                    n={n}
                    {editor_assigns(assigns)}
                  />
                  <.step_summary
                    :if={@open != step.id}
                    step={step}
                    n={n}
                    last={n == length(@campaign.steps)}
                    results={step_results(@results, step)}
                    read_only={@read_only or @locked}
                    config={@config}
                  />
                </li>
                <li :if={@open == "new"} id="step-new">
                  <.step_editor n={length(@campaign.steps) + 1} {editor_assigns(assigns)} />
                </li>
              </ol>
              <.empty :if={@campaign.steps == [] and @open != "new"} icon="mail" title="No steps yet">
                <p>The first letter: a welcome, when they enter, or a word a day later.</p>
              </.empty>
              <div :if={not @read_only and not @locked and @open != "new"} class="ta-actions ta-add-step">
                <button type="button" class="ta-button" phx-click="new_step">
                  <.icon name="plus" />Add a step
                </button>
              </div>
            </section>

            <section :if={@campaign.id && !@sequence && @open} class="ta-steps-section" aria-labelledby="letter-title">
              <div class="ta-subheading-row">
                <h2 id="letter-title" class="ta-section-title">The letter</h2>
              </div>
              <.step_editor n={1} {editor_assigns(assigns)} />
            </section>
          </div>
        </div>

        <aside class="ta-editor-side">
          <.status_card
            :if={@campaign.id}
            campaign={@campaign}
            read_only={@read_only}
            confirm={@confirm}
            schedule={@schedule}
            segments={@segments}
            enroll_segment={@enroll_segment}
            time_zone={@time_zone}
            locale={@locale}
          />
          <.results_card :if={@results} results={@results} campaign={@campaign} />
          <.card :if={!@campaign.id} title="Then" icon="info" id="then">
            <p class="ta-hint">
              Save the settings, then write {if @sequence, do: "its steps, the letters it sends.", else: "its letter."}
            </p>
          </.card>
          <section
            :if={@campaign.id && not @read_only && @campaign.status in ["draft", "archived"]}
            class="ta-danger-zone"
          >
            <button
              type="button"
              phx-click="delete"
              data-confirm="Delete this campaign, with its letters and its results? This cannot be undone."
              class="ta-button ta-danger ta-quiet"
            >
              <.icon name="trash-2" />Delete {@campaign.kind}
            </button>
          </section>
        </aside>
      </div>
    </.page>
    """
  end

  defp editor_assigns(assigns) do
    Map.take(assigns, [
      :step_form,
      :open,
      :language,
      :skip,
      :segments,
      :config,
      :uploads,
      :campaign,
      :read_only,
      :locked
    ])
  end

  defp step_results(nil, _step), do: nil
  defp step_results(%{steps: steps}, step), do: Enum.find(steps, &(&1.step_id == step.id))
  defp step_results(_results, _step), do: nil

  # ── The settings card ───────────────────────────────────────────

  attr :settings, :any, required: true
  attr :campaign, Campaign, required: true
  attr :conditions, :map, required: true
  attr :segments, :list, required: true
  attr :read_only, :boolean, required: true
  attr :config, :any, required: true

  defp settings_card(assigns) do
    trigger = Form.input_value(assigns.settings, :trigger) || %{"type" => "manual"}
    campaigns = assigns.config.campaigns

    assigns =
      assign(assigns,
        trigger_type: trigger["type"] || trigger[:type],
        trigger_event: trigger["event"] || trigger[:event] || "",
        events: Audience.events(Audience.current()),
        from_name: from_name(campaigns.from),
        sequence: assigns.campaign.kind == "sequence"
      )

    ~H"""
    <.card title="Settings" icon="settings" id="settings">
      <.form for={@settings} id="campaign-form" phx-change="validate" phx-submit="save">
        <fieldset disabled={@read_only}>
          <.input field={@settings[:name]} label="Name" maxlength="160" placeholder={if @sequence, do: "Onboarding", else: "The spring update"} />

          <div class="ta-field">
            <span class="ta-label" id="purpose-label">Purpose</span>
            <div class="ta-choices ta-choices-wide" role="radiogroup" aria-labelledby="purpose-label">
              <label :for={{value, label, text} <- purposes()} class="ta-choice ta-choice-text">
                <input
                  type="radio"
                  name="campaign[purpose]"
                  value={value}
                  checked={Form.input_value(@settings, :purpose) == value}
                />
                <span><strong>{label}</strong><span class="ta-hint">{text}</span></span>
              </label>
            </div>
          </div>

          <div :if={@sequence} class="ta-field">
            <span class="ta-label" id="trigger-label">It starts</span>
            <div class="ta-choices" role="radiogroup" aria-labelledby="trigger-label">
              <label class="ta-choice">
                <input type="radio" name="campaign[trigger_type]" value="event" checked={@trigger_type == "event"} />
                <.icon name="zap" />When something happens
              </label>
              <label class="ta-choice">
                <input type="radio" name="campaign[trigger_type]" value="manual" checked={@trigger_type != "event"} />
                <.icon name="users" />By hand
              </label>
            </div>
            <div :if={@trigger_type == "event"} class="ta-field ta-trigger-event">
              <label for="campaign_trigger_event">The event</label>
              <input
                type="text"
                id="campaign_trigger_event"
                name="campaign[trigger_event]"
                value={@trigger_event}
                list="campaign-events"
                class="ta-input"
                maxlength="64"
                placeholder="signed_up"
                autocomplete="off"
                phx-debounce="300"
              />
              <datalist id="campaign-events">
                <option :for={{name, label} <- @events} value={name}>{label}</option>
              </datalist>
              <p class="ta-hint">
                A person enters when your app calls <code>Tayori.track(person_id, "{if @trigger_event == "", do: "signed_up", else: @trigger_event}")</code>.
              </p>
            </div>
            <p :if={@trigger_type != "event"} class="ta-hint">
              People enter from this page, once it is started, or from your app with
              <code>Tayori.Campaigns.enroll/2</code>.
            </p>
            <p :for={error <- shown_errors(@settings[:trigger])} class="ta-error">Its event {error}.</p>
          </div>

          <div :if={@sequence} class="ta-grid-2">
            <.input
              field={@settings[:min_gap_hours]}
              type="number"
              label="Hours between two letters, at least"
              min="0"
              hint="A step whose time comes sooner waits."
            />
            <.input
              field={@settings[:max_days]}
              type="number"
              label="Days in the sequence, at most"
              min="1"
              hint="Optional. After it, a person leaves."
            />
          </div>

          <details class="ta-more" open={Form.input_value(@settings, :from_name) not in [nil, ""] or Form.input_value(@settings, :reply_to) not in [nil, ""]}>
            <summary><.icon name="mail" />Sender</summary>
            <div class="ta-more-body ta-grid-2">
              <.input
                field={@settings[:from_name]}
                label="From"
                maxlength="160"
                placeholder={@from_name}
                hint={"When not #{@from_name || "the app's"}."}
              />
              <.input
                field={@settings[:reply_to]}
                type="email"
                label="Replies go to"
                maxlength="320"
                placeholder={@config.campaigns.reply_to || "The sender"}
              />
            </div>
          </details>
        </fieldset>
      </.form>

      <div class="ta-campaign-conditions">
        <.live_component
          module={ConditionBuilder}
          id="audience"
          label={if @sequence, do: "Who may enter", else: "Who gets it"}
          hint={
            if @sequence,
              do: "Only these people enter, on the event or by hand. No rule: anyone.",
              else: "A rule “A segment” sends it to a saved segment; or write the rules here."
          }
          condition={@conditions["audience"]}
          count={if @sequence, do: :count, else: :sample}
          segments={@segments}
          read_only={@read_only}
        />
        <.live_component
          :if={@sequence}
          module={ConditionBuilder}
          id="goal"
          label="Goal"
          hint="A person who reaches it leaves the sequence, done: they get no more of its letters."
          empty="No goal: people stay until the last step."
          condition={@conditions["goal"]}
          segments={@segments}
          read_only={@read_only}
        />
      </div>

      <div :if={not @read_only} class="ta-actions ta-settings-actions">
        <button type="submit" form="campaign-form" class="ta-button ta-primary">
          {if @campaign.id, do: "Save settings", else: "Save #{@campaign.kind}"}
        </button>
      </div>
    </.card>
    """
  end

  defp purposes do
    [
      {"product", "Product", "What the product needs to say: a welcome, a hand to start."},
      {"marketing", "Marketing",
       "News and offers. A person can refuse marketing and keep the rest."}
    ]
  end

  defp from_name({name, _address}), do: name
  defp from_name(_address), do: nil

  # ── A step ──────────────────────────────────────────────────────

  attr :step, Step, required: true
  attr :n, :integer, required: true
  attr :last, :boolean, required: true
  attr :results, :map, default: nil
  attr :read_only, :boolean, required: true
  attr :config, :any, required: true

  defp step_summary(assigns) do
    letter =
      Enum.find(assigns.step.letters, &(&1.locale == hd(assigns.config.locales))) ||
        List.first(assigns.step.letters)

    attributes = Audience.attributes(Audience.current())

    assigns =
      assign(assigns,
        letter: letter,
        skip: assigns.step.skip_if && Tayori.Conditions.describe(assigns.step.skip_if, attributes)
      )

    ~H"""
    <article class="ta-card ta-step" aria-labelledby={"step-#{@step.id}-title"}>
      <div class="ta-step-head">
        <span class="ta-step-number" aria-hidden="true">{@n}</span>
        <div class="ta-step-main">
          <h3 id={"step-#{@step.id}-title"} class="ta-step-when">
            <span class="ta-visually-hidden">Step {@n}: </span>{wait_text(@step.wait)}
          </h3>
          <p class="ta-step-subject">
            {if @letter, do: @letter.subject, else: "No letter yet"}
          </p>
          <p :if={@skip} class="ta-hint"><.icon name="funnel" />Skipped if {lower_first(@skip)}.</p>
          <p :if={length(@step.letters) > 1} class="ta-languages-used">
            {@step.letters |> Enum.map(& &1.locale) |> Enum.join(" · ")}
          </p>
          <p :if={@results} class="ta-step-results">
            <span>{@results.sent} sent</span>
            <span :if={@results.skipped > 0}>{@results.skipped} skipped</span>
            <span :if={@results.failed > 0} class="ta-error">{@results.failed} failed</span>
            <span :if={@results.bounced > 0}>{@results.bounced} bounced</span>
            <span :if={@results.goal_after > 0}>{@results.goal_after} reached the goal after it</span>
          </p>
        </div>
        <div class="ta-row-actions">
          <button
            :if={not @read_only}
            type="button"
            class="ta-icon-button"
            phx-click="move_step"
            phx-value-id={@step.id}
            phx-value-to="up"
            disabled={@n == 1}
            aria-label={"Move step #{@n} up"}
          >
            <.icon name="chevron-up" />
          </button>
          <button
            :if={not @read_only}
            type="button"
            class="ta-icon-button"
            phx-click="move_step"
            phx-value-id={@step.id}
            phx-value-to="down"
            disabled={@last}
            aria-label={"Move step #{@n} down"}
          >
            <.icon name="chevron-down" />
          </button>
          <button
            type="button"
            class="ta-icon-button"
            phx-click="open_step"
            phx-value-id={@step.id}
            aria-label={if @read_only, do: "Read step #{@n}", else: "Edit step #{@n}"}
          >
            <.icon name={if @read_only, do: "eye", else: "pencil"} />
          </button>
          <button
            :if={not @read_only}
            type="button"
            class="ta-icon-button"
            phx-click="delete_step"
            phx-value-id={@step.id}
            data-confirm={"Delete step #{@n}, in every language? Its results stay."}
            aria-label={"Delete step #{@n}"}
          >
            <.icon name="trash-2" />
          </button>
        </div>
      </div>
    </article>
    """
  end

  attr :n, :integer, required: true
  attr :step_form, :any, required: true
  attr :open, :string, required: true
  attr :language, :string, required: true
  attr :skip, :map, default: nil
  attr :segments, :list, required: true
  attr :config, :any, required: true
  attr :uploads, :any, default: nil
  attr :campaign, Campaign, required: true
  attr :read_only, :boolean, required: true
  attr :locked, :boolean, required: true

  defp step_editor(assigns) do
    wait = Form.input_value(assigns.step_form, :wait)
    wait = if is_integer(wait), do: wait, else: 0

    assigns =
      assign(assigns,
        sequence: assigns.campaign.kind == "sequence",
        present: present_locales(assigns.step_form),
        days: div(wait, 1440),
        hours: div(rem(wait, 1440), 60),
        minutes: rem(wait, 60),
        disabled: assigns.read_only or assigns.locked
      )

    ~H"""
    <article class="ta-card ta-step ta-step-open" aria-label={if @sequence, do: "Step #{@n}", else: "The letter"}>
      <.form for={@step_form} id="step-form" phx-change="validate_step" phx-submit="save_step">
        <fieldset disabled={@disabled}>
          <div :if={@sequence} class="ta-field">
            <span class="ta-label" id="wait-label">Step {@n} goes after</span>
            <div class="ta-wait" role="group" aria-labelledby="wait-label">
              <label class="ta-wait-part">
                <input type="number" name="step[wait_days]" value={@days} min="0" step="1" class="ta-input" />
                <span>days</span>
              </label>
              <label class="ta-wait-part">
                <input type="number" name="step[wait_hours]" value={@hours} min="0" max="23" step="1" class="ta-input" />
                <span>hours</span>
              </label>
              <input :if={@minutes > 0} type="hidden" name="step[wait_minutes]" value={@minutes} />
              <span class="ta-hint">from when the person entered.</span>
            </div>
            <p :for={error <- shown_errors(@step_form[:wait])} class="ta-error">{error}</p>
          </div>

          <div :if={length(@config.locales) > 1} class="ta-languages" role="tablist" aria-label="Languages">
            <button
              :for={locale <- @present}
              type="button"
              role="tab"
              aria-selected={to_string(locale == @language)}
              phx-click="language"
              phx-value-locale={locale}
            >
              {Tayori.Locales.name(locale)}
            </button>
            <button
              :for={locale <- @config.locales -- @present}
              :if={not @disabled}
              type="button"
              class="ta-add-language"
              phx-click="add_language"
              phx-value-locale={locale}
            >
              <.icon name="plus" />{Tayori.Locales.name(locale)}
            </button>
          </div>
          <p :for={error <- shown_errors(@step_form[:letters])} class="ta-error">{error}</p>

          <.inputs_for :let={l} field={@step_form[:letters]}>
            <section class="ta-translation" hidden={l[:locale].value != @language} aria-label={Tayori.Locales.name(l[:locale].value)}>
              <input type="hidden" name={l[:locale].name} value={l[:locale].value} />
              <.input field={l[:subject]} label="Subject" maxlength="255" placeholder="Welcome, {{first_name|there}}" />
              <.input
                field={l[:preheader]}
                label="Preheader"
                maxlength="255"
                hint="The line a mail client shows after the subject. Optional."
              />
              <div class="ta-field ta-body-field ta-letter-body">
                <label id={"#{editor_id(@open, l[:locale].value)}-label"}>Letter</label>
                <Kotoba.Components.kotoba
                  id={editor_id(@open, l[:locale].value)}
                  field={l[:body]}
                  label_id={"#{editor_id(@open, l[:locale].value)}-label"}
                  features={Letter.features()}
                  uploads={@uploads && @uploads[upload_name(@config.locales, l[:locale].value)]}
                  placeholder="Write as you would to one person. {{first_name}} is their first name."
                  readonly={@disabled}
                />
              </div>
              <div class="ta-grid-2">
                <.input field={l[:cta_label]} label="Button" maxlength="80" placeholder="Open your dashboard" hint="Optional." />
                <.input field={l[:cta_url]} label="Its address" maxlength="2048" placeholder="https://… or {{dashboard_url}}" />
              </div>
              <label :if={not @disabled and l[:locale].value != hd(@config.locales)} class="ta-remove-language">
                <input type="checkbox" name="step[letters_drop][]" value={l.index} class="ta-visually-hidden" /><.icon name="trash-2" />Remove the {Tayori.Locales.name(l[:locale].value)} letter
              </label>
            </section>
          </.inputs_for>
          <input type="hidden" name="step[letters_drop][]" />
          <p class="ta-hint ta-merge-hint">
            Merge tags: <code>{"{{name}}"}</code>, <code>{"{{email}}"}</code>, and what your app gives of each
            person, <code>{"{{first_name|there}}"}</code> with a word for those who have none.
          </p>
        </fieldset>
      </.form>

      <div :if={@sequence} class="ta-step-skip">
        <.live_component
          module={ConditionBuilder}
          id={"skip-#{@open}"}
          label="Skip it if"
          hint="When its time comes, a person who matches these rules does not get it, and goes on to the next step. No rule: everyone gets it."
          empty="Never skipped."
          condition={@skip}
          segments={@segments}
          read_only={@disabled}
        />
      </div>

      <div :if={not @disabled} class="ta-actions">
        <button type="submit" form="step-form" class="ta-button ta-primary">
          {cond do
            not @sequence -> "Save letter"
            @open == "new" -> "Add step"
            true -> "Save step"
          end}
        </button>
        <button :if={@sequence} type="button" class="ta-button ta-quiet" phx-click="close_step">
          {if @open == "new", do: "Cancel", else: "Close"}
        </button>
      </div>
      <div :if={@disabled and @sequence} class="ta-actions">
        <button type="button" class="ta-button ta-quiet" phx-click="close_step">Close</button>
      </div>
    </article>
    """
  end

  defp present_locales(form) do
    form.source
    |> Ecto.Changeset.get_assoc(:letters, :struct)
    |> Enum.map(& &1.locale)
  end

  # The errors of a field once the form was sent or changed.
  defp shown_errors(%Phoenix.HTML.FormField{form: form, errors: errors}) do
    if form.source.action, do: Enum.map(errors, &translate_error/1), else: []
  end

  @doc false
  def wait_text(0), do: "When they enter"

  def wait_text(minutes) do
    days = div(minutes, 1440)
    hours = div(rem(minutes, 1440), 60)
    rest = rem(minutes, 60)

    parts =
      [{days, "day"}, {hours, "hour"}, {rest, "minute"}]
      |> Enum.reject(fn {n, _unit} -> n == 0 end)
      |> Enum.map(fn {n, unit} -> "#{n} #{unit}#{if n == 1, do: "", else: "s"}" end)

    "After " <> Enum.join(parts, " ")
  end

  defp lower_first(<<first::utf8, second::utf8, rest::binary>> = text) do
    if String.downcase(<<second::utf8>>) == <<second::utf8>>,
      do: String.downcase(<<first::utf8>>) <> <<second::utf8, rest::binary>>,
      else: text
  end

  defp lower_first(text), do: text

  # ── The status card ─────────────────────────────────────────────

  attr :campaign, Campaign, required: true
  attr :read_only, :boolean, required: true
  attr :confirm, :map, default: nil
  attr :schedule, :any, required: true
  attr :segments, :list, required: true
  attr :enroll_segment, :string, required: true
  attr :time_zone, :string, required: true
  attr :locale, :string, required: true

  defp status_card(assigns) do
    ~H"""
    <.card title="Status" icon="send" id="status">
      <p class="ta-status-line">
        <CampaignsLive.campaign_status campaign={@campaign} />
      </p>
      <p class="ta-hint">{status_hint(@campaign)}</p>

      <.confirm :if={@confirm && not @read_only} confirm={@confirm} campaign={@campaign} />

      <div :if={not @read_only and @confirm == nil} class="ta-status-actions">
        <%= if @campaign.kind == "sequence" do %>
          <div class="ta-actions">
            <button :if={@campaign.status == "draft"} type="button" class="ta-button ta-primary" phx-click="status" phx-value-to="start">
              <.icon name="play" />Start
            </button>
            <button :if={@campaign.status == "active"} type="button" class="ta-button" phx-click="status" phx-value-to="pause">
              <.icon name="pause" />Pause
            </button>
            <button :if={@campaign.status == "paused"} type="button" class="ta-button ta-primary" phx-click="status" phx-value-to="resume">
              <.icon name="play" />Resume
            </button>
            <button
              :if={@campaign.status in ["active", "paused"]}
              type="button"
              class="ta-button ta-quiet"
              phx-click="status"
              phx-value-to="archive"
              data-confirm="Archive this sequence? No one enters, and its people leave it. It cannot start again."
            >
              <.icon name="archive" />Archive
            </button>
          </div>
          <form :if={@campaign.status == "active"} id="enroll-form" phx-submit="enroll" class="ta-enroll">
            <div class="ta-field">
              <label for="enroll-segment">Take people in now</label>
              <select id="enroll-segment" name="segment" class="ta-input">
                <option value="" selected={@enroll_segment == ""}>Everyone who may enter</option>
                <option :for={{id, name} <- @segments} value={id} selected={@enroll_segment == id}>
                  The segment “{name}”
                </option>
              </select>
              <p class="ta-hint">Those in it before stay where they are.</p>
            </div>
            <button type="submit" class="ta-button ta-small"><.icon name="users" />Take them in</button>
          </form>
        <% else %>
          <.form
            :if={@campaign.status in ["draft", "scheduled"]}
            for={@schedule}
            id="schedule-form"
            phx-change="schedule_change"
            phx-submit="schedule"
          >
            <div class="ta-field">
              <label id="schedule-label">{if @campaign.status == "scheduled", do: "Move it to", else: "Send at"}</label>
              <Koyomi.Components.datetime_picker
                field={@schedule[:at]}
                label_id="schedule-label"
                time_zone={@time_zone}
                locale={@locale}
                rules={[min: :today]}
              />
              <p :if={@time_zone == "Etc/UTC"} class="ta-hint">The time is in UTC.</p>
            </div>
            <div class="ta-actions">
              <button type="submit" class="ta-button"><.icon name="calendar" />Schedule</button>
              <button type="button" class="ta-button ta-primary" phx-click="send_now">
                <.icon name="send" />Send now
              </button>
            </div>
          </.form>
          <div class="ta-actions ta-status-more">
            <button
              :if={@campaign.status == "scheduled"}
              type="button"
              class="ta-button ta-quiet"
              phx-click="cancel_schedule"
            >
              <.icon name="x" />Cancel the schedule
            </button>
            <button
              :if={@campaign.status in ["draft", "scheduled", "sent"]}
              type="button"
              class="ta-button ta-quiet"
              phx-click="status"
              phx-value-to="archive"
              data-confirm="Archive this broadcast? A scheduled one does not go."
            >
              <.icon name="archive" />Archive
            </button>
          </div>
        <% end %>
      </div>
    </.card>
    """
  end

  attr :confirm, :map, required: true
  attr :campaign, Campaign, required: true

  defp confirm(assigns) do
    ~H"""
    <div class="ta-confirm" role="group" aria-labelledby="confirm-text" id="confirm">
      <p id="confirm-text">
        <%= case @confirm.action do %>
          <% :send_now -> %>
            It goes now to the {ConditionBuilder.people(@confirm.count)} of its audience, less those who unsubscribed or cannot be written to.
          <% {:schedule, at} -> %>
            It goes <.time at={at} /> to the people of its audience then: {ConditionBuilder.people(@confirm.count)} today.
          <% {:enroll, _segment} -> %>
            {ConditionBuilder.people(@confirm.count) |> String.capitalize()} may enter now. Each gets the first letter at its time.
        <% end %>
      </p>
      <div class="ta-actions">
        <button
          type="button"
          class="ta-button ta-primary"
          phx-click="confirm"
          phx-mounted={JS.focus()}
          disabled={@confirm.count == 0}
        >
          <%= case @confirm.action do %>
            <% :send_now -> %>
              <.icon name="send" />Send to {ConditionBuilder.people(@confirm.count)}
            <% {:schedule, _at} -> %>
              <.icon name="calendar" />Schedule it
            <% {:enroll, _segment} -> %>
              <.icon name="users" />Take in {ConditionBuilder.people(@confirm.count)}
          <% end %>
        </button>
        <button type="button" class="ta-button ta-quiet" phx-click="not_now">Not now</button>
      </div>
    </div>
    """
  end

  defp status_hint(%Campaign{kind: "sequence", status: "draft"}),
    do: "Nothing goes yet. Start it when its letters are written."

  defp status_hint(%Campaign{kind: "sequence", status: "active"} = c),
    do:
      "It takes people in #{if c.trigger["type"] == "event", do: "on “#{c.trigger["event"]}”", else: "by hand"}, and writes to them at their times."

  defp status_hint(%Campaign{kind: "sequence", status: "paused"}),
    do: "No one enters, and no letter goes. Its people wait where they are."

  defp status_hint(%Campaign{status: "archived"}), do: "It is done: it writes to no one."

  defp status_hint(%Campaign{kind: "broadcast", status: "draft"}),
    do: "It goes when you send it, now or at a time."

  defp status_hint(%Campaign{kind: "broadcast", status: "scheduled"}),
    do: "Its audience is read when it goes."

  defp status_hint(%Campaign{kind: "broadcast", status: "sending"}),
    do: "Its letters are going now."

  defp status_hint(%Campaign{kind: "broadcast", status: "sent"}),
    do: "It went. Its letter stays as it was."

  defp status_hint(_campaign), do: ""

  # ── The results ─────────────────────────────────────────────────

  attr :results, :map, required: true
  attr :campaign, Campaign, required: true

  defp results_card(%{campaign: %Campaign{kind: "broadcast"}} = assigns) do
    ~H"""
    <.card title="Results" icon="chart-column" id="results">
      <dl class="ta-stats">
        <div><dt>Recipients</dt><dd>{ConditionBuilder.delimit(@results.recipients)}</dd></div>
        <div><dt>Sent</dt><dd>{ConditionBuilder.delimit(@results.sent)}</dd></div>
        <div><dt>Failed</dt><dd>{@results.failed}</dd></div>
        <div><dt>Bounced</dt><dd>{@results.bounced}</dd></div>
        <div><dt>Complained</dt><dd>{@results.complained}</dd></div>
        <div :if={@results.skipped > 0}><dt>Skipped</dt><dd>{@results.skipped}</dd></div>
      </dl>
    </.card>
    """
  end

  defp results_card(assigns) do
    assigns = assign(assigns, steps: Enum.with_index(assigns.results.steps, 1))

    ~H"""
    <.card title="Results" icon="chart-column" id="results">
      <dl class="ta-stats">
        <div><dt>Entered</dt><dd>{ConditionBuilder.delimit(@results.entered)}</dd></div>
        <div><dt>In it now</dt><dd>{ConditionBuilder.delimit(@results.active)}</dd></div>
        <div>
          <dt>Reached the goal</dt>
          <dd>
            {ConditionBuilder.delimit(@results.goal)}<span :if={@results.goal_rate} class="ta-hint"> · {percent(@results.goal_rate)}</span>
          </dd>
        </div>
      </dl>
      <ul :if={@results.ended != %{}} class="ta-sources" aria-label="Left, by reason">
        <li :for={{reason, n} <- Enum.sort_by(@results.ended, &(-elem(&1, 1)))}>
          <span>{reason_label(reason)}</span><span>{n}</span>
        </li>
      </ul>
      <table :if={@steps != []} class="ta-table ta-results-table">
        <caption class="ta-visually-hidden">The letters of each step</caption>
        <thead>
          <tr>
            <th scope="col">Step</th>
            <th scope="col">Sent</th>
            <th scope="col">Skipped</th>
            <th scope="col">Failed</th>
            <th scope="col">Bounced</th>
            <th scope="col"><abbr title="Reached the goal after this letter">Goal</abbr></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{step, n} <- @steps}>
            <th scope="row">{n}</th>
            <td>{step.sent}</td>
            <td>{step.skipped}</td>
            <td>{step.failed}</td>
            <td>{step.bounced}</td>
            <td>{step.goal_after}</td>
          </tr>
        </tbody>
      </table>
    </.card>
    """
  end

  defp percent(rate), do: "#{round(rate * 100)}%"

  defp reason_label("goal"), do: "Reached the goal"
  defp reason_label("finished"), do: "Got every letter"
  defp reason_label("expired"), do: "Stayed the most days"
  defp reason_label("left"), do: "Left the app"
  defp reason_label("unsubscribed"), do: "Unsubscribed"
  defp reason_label("cannot_email"), do: "Cannot be written to"
  defp reason_label("stopped"), do: "Stopped, archived"
  defp reason_label(other), do: to_string(other)

  # ── The preview ─────────────────────────────────────────────────

  attr :preview, :map, required: true
  attr :campaign, Campaign, required: true
  attr :read_only, :boolean, required: true
  attr :test_address, :string, required: true

  defp preview_card(assigns) do
    ~H"""
    <section class="ta-card ta-letter-preview" aria-label="Preview">
      <form id="preview-form" phx-change="preview" phx-submit="preview" class="ta-preview-controls">
        <div :if={@campaign.kind == "sequence"} class="ta-field">
          <label for="preview-step">Step</label>
          <select id="preview-step" name="step" class="ta-input">
            <option :for={{step, n} <- Enum.with_index(@campaign.steps, 1)} value={step.id} selected={step.id == @preview.step_id}>
              {n}. {wait_text(step.wait)}
            </option>
          </select>
        </div>
        <div class="ta-field">
          <label for="preview-person">As</label>
          <select id="preview-person" name="person" class="ta-input">
            <option :if={@preview.people == []} value="">No one in its audience</option>
            <option :for={person <- @preview.people} value={person.id} selected={person.id == @preview.person}>
              {person.name || person.email || person.id}{if person.name && person.email, do: " · #{person.email}"}
            </option>
          </select>
        </div>
        <div class="ta-field">
          <label for="preview-person-id">Or a person's id</label>
          <input
            id="preview-person-id"
            name="person_id"
            value={@preview.typed}
            class="ta-input"
            placeholder="user:42"
            autocomplete="off"
            phx-debounce="400"
          />
        </div>
      </form>

      <p :if={@preview.problem} class="ta-notice"><.icon name="info" />{@preview.problem}</p>

      <div :if={@preview.email} class="ta-letter-envelope">
        <dl class="ta-facts">
          <div><dt>From</dt><dd>{address_text(@preview.email.from)}</dd></div>
          <div><dt>To</dt><dd>{address_text(hd(@preview.email.to))}</dd></div>
          <div><dt>Subject</dt><dd><strong>{@preview.email.subject}</strong></dd></div>
        </dl>
        <p :if={@preview.missing != []} class="ta-hint ta-warning" role="status">
          <.icon name="triangle-alert" />
          {@preview.recipient.name || "This person"} has no value for
          {Enum.map_join(@preview.missing, ", ", &"{{#{&1}}}")}: {if length(@preview.missing) == 1, do: "it is", else: "they are"} left empty, or show its fallback.
        </p>
        <iframe
          class="ta-letter-frame"
          title={"The letter, as #{@preview.recipient.name || "a person"} gets it"}
          sandbox=""
          srcdoc={@preview.email.html_body}
        ></iframe>
        <p class="ta-hint">The letter as it is saved.</p>
      </div>

      <form :if={not @read_only and @preview.email} id="test-form" phx-submit="test" class="ta-test-form">
        <div class="ta-field ta-grow">
          <label for="test-address">Send a test to</label>
          <input id="test-address" type="email" name="address" value={@test_address} class="ta-input" autocomplete="email" placeholder="you@example.com" />
        </div>
        <button type="submit" class="ta-button"><.icon name="mail" />Send a test</button>
      </form>
      <p :if={not @read_only and @preview.email} class="ta-hint">
        The subject begins with “[Test]”. It is not counted in the results.
      </p>
    </section>
    """
  end

  defp address_text({"", address}), do: address
  defp address_text({nil, address}), do: address
  defp address_text({name, address}), do: "#{name} <#{address}>"
  defp address_text(address), do: to_string(address)
end
