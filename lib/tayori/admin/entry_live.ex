defmodule Tayori.Admin.EntryLive do
  @moduledoc false
  # Writes an entry: its title, summary and body in each language (the
  # body in Kotoba's editor, with attachments), its categories and
  # segments, and when it is published.

  use Phoenix.LiveView, layout: false

  import Tayori.Admin.Components

  alias Tayori.Admin.Writer
  alias Tayori.{AI, Entries, Entry, Resolver, Translation}

  @accept ~w(.png .jpg .jpeg .gif .webp .pdf .mp4 .webm)
  @max_file_size 25_000_000

  @impl true
  def mount(params, _session, socket) do
    entry =
      case socket.assigns.live_action do
        :new -> Entries.new()
        :edit -> fetch!(params["id"])
      end

    locales = socket.assigns.config.locales

    socket =
      socket
      |> assign(
        entry: entry,
        language: List.first(locales),
        segment_groups: Resolver.segment_groups(socket.assigns.resolver),
        page_title: if(entry.id, do: "Edit entry", else: "New entry"),
        now: DateTime.utc_now(),
        ai: socket.assigns.access == :all and AI.configured?(),
        ai_open: false,
        writers: %{}
      )
      |> assign_form(Entries.change(entry))
      |> assign_schedule(entry.published_at)
      |> allow_uploads(locales)

    {:ok, socket}
  end

  defp fetch!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Entries.get!(uuid)
      :error -> raise Tayori.Admin.NotFound
    end
  rescue
    error in Ecto.NoResultsError ->
      reraise Tayori.Admin.NotFound, [message: error.message], __STACKTRACE__
  end

  # One upload for each language: Kotoba puts each file in the editor it
  # was dropped on.
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
  # request, so they are a short, known list of atoms.
  defp upload_name(locales, locale) do
    index = Enum.find_index(locales, &(&1 == locale))
    :"tayori_attachments_#{index}"
  end

  defp editor_id(locale), do: "tayori-body-#{locale}"

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :entry))
  end

  defp assign_schedule(socket, at) do
    value = if at && DateTime.compare(at, DateTime.utc_now()) == :gt, do: at
    assign(socket, :schedule, to_form(%{"at" => value}, as: :schedule))
  end

  @impl true
  def handle_event("validate", %{"entry" => params} = all, socket) do
    socket = consume_all(socket)

    changeset =
      socket.assigns.entry |> Entries.change(normalize(params)) |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(:schedule, to_form(Map.get(all, "schedule", %{}), as: :schedule))}
  end

  def handle_event("language", %{"locale" => locale}, socket) do
    if locale in socket.assigns.config.locales do
      {:noreply, assign(socket, :language, locale)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_language", %{"locale" => locale}, socket) do
    with :all <- socket.assigns.access,
         true <- locale in socket.assigns.config.locales do
      changeset = socket.assigns.form.source
      translations = Ecto.Changeset.get_assoc(changeset, :translations)

      changeset =
        Ecto.Changeset.put_assoc(
          changeset,
          :translations,
          translations ++ [%Translation{locale: locale}]
        )

      {:noreply, socket |> assign_form(changeset) |> assign(:language, locale)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save", %{"entry" => params} = all, %{assigns: %{access: :all}} = socket) do
    socket = consume_all(socket)
    attrs = normalize(params)

    case save(socket, attrs, all["intent"], schedule_time(all)) do
      {:ok, entry, message} ->
        socket =
          socket
          |> put_flash(:info, message)
          |> assign(entry: entry, now: DateTime.utc_now())
          |> assign_form(Entries.change(entry))
          |> assign_schedule(entry.published_at)

        if socket.assigns.live_action == :new do
          {:noreply, push_navigate(socket, to: socket.assigns.prefix <> "/" <> entry.id)}
        else
          {:noreply, socket}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "The entry was not saved: see the fields below.")
         |> assign_form(Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("delete", _params, %{assigns: %{access: :all, entry: %Entry{id: id}}} = socket)
      when not is_nil(id) do
    {:ok, _} = Entries.delete(socket.assigns.entry)

    {:noreply,
     socket
     |> put_flash(:info, "The entry was deleted.")
     |> push_navigate(to: socket.assigns.prefix)}
  end

  # The AI: a draft from notes, a translation from the first language, and
  # the actions of the editor's Assist menu on a passage.

  def handle_event("ai_toggle", _params, socket) do
    {:noreply, update(socket, :ai_open, &(!&1))}
  end

  def handle_event("ai_draft", %{"notes" => notes}, %{assigns: %{ai: true}} = socket) do
    case String.trim(notes) do
      "" ->
        {:noreply, socket}

      notes ->
        locale = socket.assigns.language

        {:noreply,
         Writer.start(
           socket,
           Kotoba.Live.stream_ref(),
           editor_id(locale),
           locale,
           :draft,
           {:draft, notes, locale},
           label: "Draft"
         )}
    end
  end

  def handle_event("ai_translate", _params, %{assigns: %{ai: true}} = socket) do
    [first | _] = socket.assigns.config.locales
    to = socket.assigns.language

    case source(socket.assigns.form.source, first) do
      %{title: title} = source when title not in [nil, ""] and to != first ->
        {:noreply,
         Writer.start(
           socket,
           Kotoba.Live.stream_ref(),
           editor_id(to),
           to,
           :translate,
           {:translate, source, first, to},
           label: "Translation"
         )}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Write the #{Tayori.Locales.name(first)} version first.")}
    end
  end

  def handle_event(
        "kotoba:assist",
        %{"id" => editor, "ref" => ref, "action" => action, "text" => text},
        %{assigns: %{ai: true}} = socket
      ) do
    with locale when is_binary(locale) <- locale_of(socket, editor),
         true <- String.trim(text) != "" do
      {:noreply,
       Writer.start(socket, ref, editor, locale, :assist, {:assist, action, text, locale},
         at: :selection,
         label: action_label(action)
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("kotoba:suggestion", %{"ref" => ref, "action" => action}, socket)
      when action in ["stop", "reject"] do
    {:noreply, Writer.stop(socket, ref)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:tayori_ai, ref, message}, socket) do
    case Writer.handle(socket, ref, message) do
      {socket, nil} -> {:noreply, socket}
      {socket, {locale, fields}} -> {:noreply, put_fields(socket, locale, fields)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp locale_of(socket, editor) do
    Enum.find(socket.assigns.config.locales, &(editor_id(&1) == editor))
  end

  defp action_label(action) do
    Enum.find_value(AI.actions(), "AI", fn {id, label} -> if id == action, do: label end)
  end

  # The first language's version, for a translation: its body as Markdown.
  defp source(changeset, locale) do
    case changeset
         |> Ecto.Changeset.get_assoc(:translations, :struct)
         |> Enum.find(&(&1.locale == locale)) do
      nil ->
        nil

      t ->
        markdown =
          with %Kotoba.Content{doc: doc} <- t.body,
               {:ok, document} <- Kotoba.Document.parse(doc) do
            Kotoba.Renderer.to_markdown(document)
          else
            _ -> ""
          end

        %{title: t.title, summary: t.summary || "", markdown: markdown}
    end
  end

  # The title and summary of a draft or a translation go into the form; a
  # draft fills only what the admin left empty.
  defp put_fields(socket, locale, fields) do
    changeset = socket.assigns.form.source
    params = form_params(changeset)

    translations =
      Map.new(params["translations"], fn {index, t} ->
        if t["locale"] == locale do
          {index,
           t
           |> fill("title", fields.title)
           |> fill("summary", fields.summary)}
        else
          {index, t}
        end
      end)

    assign_form(
      socket,
      Entries.change(socket.assigns.entry, %{params | "translations" => translations})
    )
  end

  defp fill(t, _key, blank) when blank in [nil, ""], do: t

  defp fill(t, key, value) do
    if (t[key] || "") == "", do: Map.put(t, key, value), else: t
  end

  # The params of the form as it is now, from its changeset.
  defp form_params(changeset) do
    translations =
      changeset
      |> Ecto.Changeset.get_assoc(:translations, :struct)
      |> Enum.with_index()
      |> Map.new(fn {t, index} ->
        {Integer.to_string(index),
         %{
           "locale" => t.locale,
           "title" => t.title || "",
           "summary" => t.summary || "",
           "body" => if(t.body, do: JSON.encode!(t.body.doc), else: "")
         }}
      end)

    %{
      "slug" => Ecto.Changeset.get_field(changeset, :slug) || "",
      "categories" => Ecto.Changeset.get_field(changeset, :categories) || [],
      "segments" => Ecto.Changeset.get_field(changeset, :segments) || [],
      "translations" => translations
    }
  end

  # Saves the fields, then the status the admin asked for: the status
  # goes through publish/unpublish, so that an entry is announced when it
  # is published, and announced again after it was unpublished.
  defp save(socket, attrs, intent, at) do
    %{entry: entry, resolver: resolver, user: user} = socket.assigns
    attrs = Map.delete(attrs, "published_at")

    saved =
      case entry do
        %Entry{id: nil} -> Entries.create(attrs, author: Resolver.author(resolver, user))
        %Entry{} -> Entries.update(entry, attrs)
      end

    with {:ok, saved} <- saved,
         {:ok, saved, message} <- apply_intent(saved, intent, at) do
      {:ok, Entries.get!(saved.id), message}
    end
  end

  defp apply_intent(entry, "publish", at) do
    now = DateTime.utc_now()
    later? = match?(%DateTime{}, at) and DateTime.compare(at, now) == :gt

    with {:ok, entry} <- Entries.publish(entry, if(later?, do: at, else: now)) do
      {:ok, entry, if(later?, do: "The entry is scheduled.", else: "The entry is published.")}
    end
  end

  defp apply_intent(entry, "unpublish", _at) do
    with {:ok, entry} <- Entries.unpublish(entry), do: {:ok, entry, "The entry is a draft again."}
  end

  defp apply_intent(entry, _save, _at), do: {:ok, entry, "Saved."}

  defp schedule_time(%{"schedule" => %{"at" => at}}) when is_binary(at) and at != "" do
    case DateTime.from_iso8601(at) do
      {:ok, at, _offset} -> at
      {:error, _} -> nil
    end
  end

  defp schedule_time(_params), do: nil

  # The categories are typed as one line, separated by commas.
  defp normalize(params) do
    params
    |> Map.update("categories", [], fn
      text when is_binary(text) -> String.split(text, ",")
      list when is_list(list) -> list
    end)
    |> Map.put_new("segments", [])
  end

  defp consume_all(socket) do
    Enum.reduce(socket.assigns.config.locales, socket, &consume(&2, &1))
  end

  defp consume(socket, locale) do
    opts = if socket.assigns.storage, do: [storage: socket.assigns.storage], else: []

    Kotoba.Live.consume_uploads(
      socket,
      upload_name(socket.assigns.config.locales, locale),
      editor_id(locale),
      opts
    )
  end

  def handle_progress(name, upload, socket) do
    locale =
      Enum.find(
        socket.assigns.config.locales,
        &(upload_name(socket.assigns.config.locales, &1) == name)
      )

    if upload.done? and locale do
      {:noreply, consume(socket, locale)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        status: Entry.status(assigns.entry, assigns.now),
        present: present_locales(assigns.form),
        read_only: assigns.access != :all
      )

    ~H"""
    <.page prefix={@prefix} page={:entries} flash={@flash}>
      <div class="ta-toolbar">
        <h1>
          <.link navigate={@prefix} class="ta-back" aria-label="Entries">←</.link>
          {if @entry.id, do: "Edit entry", else: "New entry"}
        </h1>
        <div class="ta-toolbar-actions">
          <.status :if={@entry.id} entry={@entry} now={@now} />
          <button
            :if={@ai}
            type="button"
            class={["ta-button", @ai_open && "ta-pressed"]}
            phx-click="ai_toggle"
            aria-expanded={to_string(@ai_open)}
            aria-controls="ai-panel"
          >
            Write with AI
          </button>
        </div>
      </div>

      <section :if={@ai and @ai_open} id="ai-panel" class="ta-panel ta-ai" aria-label="Write with AI">
        <form id="ai-draft" phx-submit="ai_draft">
          <div class="ta-field">
            <label for="ai-notes">What shipped</label>
            <textarea
              id="ai-notes"
              name="notes"
              rows="4"
              class="ta-input"
              placeholder="The changes, as you have them: a list, commit messages, pull request titles."
            ></textarea>
          </div>
          <div class="ta-actions">
            <button type="submit" class="ta-button ta-primary" disabled={@writers != %{}}>
              Draft in {Tayori.Locales.name(@language)}
            </button>
            <button
              :if={@language != hd(@config.locales)}
              type="button"
              class="ta-button"
              phx-click="ai_translate"
              disabled={@writers != %{}}
            >
              Translate from {Tayori.Locales.name(hd(@config.locales))}
            </button>
            <span :if={@writers != %{}} class="ta-hint" role="status">Writing…</span>
          </div>
          <p class="ta-hint">
            The text comes into the editor as a suggestion: accept it, or reject it.
            Select a passage for Rewrite, Shorter, Warmer and Fix spelling, in the editor's Assist menu.
          </p>
        </form>
      </section>

      <.form
        for={@form}
        id="entry-form"
        phx-change="validate"
        phx-submit="save"
        class="ta-editor"
      >
        <fieldset disabled={@read_only} class="ta-editor-main">
          <div :if={length(@config.locales) > 1} class="ta-languages" role="tablist">
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
              :if={not @read_only}
              type="button"
              class="ta-add-language"
              phx-click="add_language"
              phx-value-locale={locale}
            >
              + {Tayori.Locales.name(locale)}
            </button>
          </div>

          <.errors field={@form[:translations]} />

          <.inputs_for :let={t} field={@form[:translations]}>
            <section
              class="ta-translation"
              hidden={t[:locale].value != @language}
              aria-label={Tayori.Locales.name(t[:locale].value)}
            >
              <input type="hidden" name={t[:locale].name} value={t[:locale].value} />
              <.input field={t[:title]} label="Title" maxlength="255" />
              <.input
                field={t[:summary]}
                type="textarea"
                label="Summary"
                rows="2"
                maxlength="500"
                hint="One or two sentences for the news panel and the emails. Optional."
              />
              <div class="ta-field">
                <label id={"#{editor_id(t[:locale].value)}-label"}>Body</label>
                <Kotoba.Components.kotoba
                  id={editor_id(t[:locale].value)}
                  field={t[:body]}
                  label_id={"#{editor_id(t[:locale].value)}-label"}
                  features={Translation.features()}
                  uploads={@uploads[upload_name(@config.locales, t[:locale].value)]}
                  placeholder="What changed, and why it matters to your people"
                  readonly={@read_only}
                  assist={if @ai, do: AI.actions()}
                />
              </div>
              <label
                :if={not @read_only and t[:locale].value != hd(@config.locales)}
                class="ta-remove-language"
              >
                <input
                  type="checkbox"
                  name="entry[translations_drop][]"
                  value={t.index}
                  class="ta-visually-hidden"
                /> Remove the {Tayori.Locales.name(t[:locale].value)} version
              </label>
            </section>
          </.inputs_for>
          <input type="hidden" name="entry[translations_drop][]" />
        </fieldset>

        <aside class="ta-editor-side">
          <section :if={not @read_only} class="ta-panel" aria-labelledby="publish-heading">
            <h2 id="publish-heading">Publication</h2>
            <p :if={@status == :published} class="ta-hint">
              Published <.time at={@entry.published_at} />. Saving changes it for its readers;
              it is not announced again.
            </p>
            <div :if={@status != :published} class="ta-field">
              <label id="schedule-label">Publish at</label>
              <Koyomi.Components.datetime_picker
                field={@schedule[:at]}
                label_id="schedule-label"
                time_zone={@time_zone}
                locale={@locale}
                rules={[min: :today]}
              />
              <p class="ta-hint">
                Leave it empty to publish now. A later time schedules it.
                <span :if={@time_zone == "Etc/UTC"}>The time is in UTC.</span>
              </p>
            </div>
            <div class="ta-actions">
              <button
                :if={@status != :published}
                type="submit"
                name="intent"
                value="publish"
                class="ta-button ta-primary"
              >
                {publish_label(@schedule)}
              </button>
              <button
                type="submit"
                name="intent"
                value="save"
                class={["ta-button", @status == :published && "ta-primary"]}
              >
                {if @status == :draft, do: "Save draft", else: "Save"}
              </button>
              <button
                :if={@status != :draft}
                type="submit"
                name="intent"
                value="unpublish"
                class="ta-button ta-quiet"
              >
                Unpublish
              </button>
            </div>
          </section>

          <fieldset disabled={@read_only} class="ta-panel">
            <legend>Details</legend>
            <.input
              field={@form[:slug]}
              label="Address"
              hint="The end of its address on the public page. Made from the title when empty."
            />
            <div class="ta-field">
              <label for="entry_categories">Categories</label>
              <input
                type="text"
                id="entry_categories"
                name="entry[categories]"
                value={Enum.join(@form[:categories].value || [], ", ")}
                placeholder="New, Improved, Fixed"
                class="ta-input"
              />
              <p class="ta-hint">Separated by commas.</p>
            </div>
            <div :if={@segment_groups != []} class="ta-field">
              <span class="ta-label">For</span>
              <p class="ta-hint">Everyone, unless you choose who it is for.</p>
              <input type="hidden" name="entry[segments][]" value="" />
              <div :for={{group, segments} <- @segment_groups} class="ta-segments">
                <span :if={group} class="ta-segment-group">{group}</span>
                <label :for={{segment, label} <- segments} class="ta-check">
                  <input
                    type="checkbox"
                    name="entry[segments][]"
                    value={segment}
                    checked={segment in (@form[:segments].value || [])}
                  />
                  {label}
                </label>
              </div>
            </div>
          </fieldset>

          <section :if={@entry.id && not @read_only} class="ta-panel ta-danger-zone">
            <button
              type="button"
              phx-click="delete"
              data-confirm="Delete this entry, in every language? This cannot be undone."
              class="ta-button ta-danger"
            >
              Delete entry
            </button>
          </section>
        </aside>
      </.form>
    </.page>
    """
  end

  defp present_locales(form) do
    form.source
    |> Ecto.Changeset.get_assoc(:translations, :struct)
    |> Enum.map(& &1.locale)
  end

  defp publish_label(schedule) do
    if schedule[:at].value in [nil, ""], do: "Publish now", else: "Schedule"
  end
end
