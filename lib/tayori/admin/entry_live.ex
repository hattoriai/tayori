defmodule Tayori.Admin.EntryLive do
  @moduledoc false
  # Writes an entry: its title, summary and body in each language (the
  # body in Kotoba's editor, with attachments), its cover, categories and
  # audience, and when it is published; with the features on, how it is
  # announced in the app and whether it is emailed. The preview shows the
  # entry as it is in the form, as readers will see it.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Kotoba.Nodes.Attachment
  alias Phoenix.HTML.Form
  alias Tayori.Admin.Writer
  alias Tayori.{AI, Categories, Config, Entries, Entry, Messages, Resolver, Translation}

  @accept ~w(.png .jpg .jpeg .gif .webp .pdf .mp4 .webm)
  @cover_accept ~w(.png .jpg .jpeg .gif .webp)
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
        writers: %{},
        categories: Categories.list(),
        mode: :write,
        preview_as: :page,
        cover: entry.cover,
        pinned: entry.pinned_at != nil,
        copied: false
      )
      |> assign_form(Entries.change(entry))
      |> assign_schedule(entry.published_at)
      |> assign_stats()
      |> allow_uploads(locales)
      |> allow_cover()

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
  # was dropped on. Only an admin who may write uploads.
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

  # The cover: one image, stored as Kotoba stores the files of the body.
  defp allow_cover(%{assigns: %{access: :all}} = socket) do
    allow_upload(socket, :tayori_cover,
      accept: @cover_accept,
      max_file_size: @max_file_size,
      max_entries: 1,
      auto_upload: true,
      progress: &handle_cover/3
    )
  end

  defp allow_cover(socket), do: socket

  def handle_cover(:tayori_cover, upload, socket) do
    if upload.done? do
      opts = if socket.assigns.storage, do: [storage: socket.assigns.storage], else: []

      result =
        consume_uploaded_entry(socket, upload, fn %{path: path} ->
          {:ok,
           Kotoba.Attachments.store(
             path,
             [name: upload.client_name, content_type: upload.client_type] ++ opts
           )}
        end)

      {:noreply, put_cover_result(socket, result)}
    else
      {:noreply, socket}
    end
  end

  defp put_cover_result(socket, {:ok, %Attachment{} = image}) do
    if Attachment.image?(image) do
      cover = %{
        "url" => image.url,
        "key" => image.key,
        "width" => image.width,
        "height" => image.height,
        "alt" => (socket.assigns.cover || %{})["alt"] || ""
      }

      assign(socket, :cover, cover)
    else
      put_flash(socket, :error, "A cover is an image: PNG, JPEG, GIF or WebP.")
    end
  end

  defp put_cover_result(socket, {:error, _reason}),
    do: put_flash(socket, :error, "The cover could not be stored.")

  # Only a published entry has readers to count.
  defp assign_stats(%{assigns: %{entry: %Entry{id: id} = entry, config: config}} = socket)
       when is_binary(id) do
    if Config.feature?(config, :analytics) and published?(entry),
      do: assign(socket, :stats, stats(entry)),
      else: assign(socket, :stats, nil)
  end

  defp assign_stats(socket), do: assign(socket, :stats, nil)

  # The last 30 days of an entry, or the days since it was published.
  defp stats(%Entry{id: id} = entry) do
    since =
      Enum.max([Date.add(Date.utc_today(), -29), DateTime.to_date(entry.published_at)], Date)

    days = Tayori.Views.by_day(id, since)

    by_source =
      Enum.reduce(days, %{}, fn {_date, sources}, acc ->
        Map.merge(acc, sources, fn _k, a, b -> a + b end)
      end)

    totals = Tayori.Views.totals([id])[id] || %{views: 0, readers: 0}
    %{totals: totals, days: days, by_source: by_source}
  end

  defp published?(%Entry{published_at: nil}), do: false

  defp published?(%Entry{published_at: at}),
    do: DateTime.compare(at, DateTime.utc_now()) != :gt

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
    socket = socket |> consume_all() |> put_cover_alt(all)

    changeset =
      socket.assigns.entry |> Entries.change(normalize(params)) |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(:schedule, to_form(Map.get(all, "schedule", %{}), as: :schedule))}
  end

  def handle_event("mode", %{"mode" => mode}, socket) when mode in ["write", "preview"] do
    {:noreply, assign(socket, :mode, String.to_existing_atom(mode))}
  end

  def handle_event("preview_as", %{"as" => as}, socket)
      when as in ["page", "panel", "announcement"] do
    {:noreply, assign(socket, :preview_as, String.to_existing_atom(as))}
  end

  def handle_event("remove_cover", _params, %{assigns: %{access: :all}} = socket) do
    {:noreply, assign(socket, :cover, nil)}
  end

  def handle_event("pinned", _params, %{assigns: %{access: :all}} = socket) do
    {:noreply, update(socket, :pinned, &(!&1))}
  end

  def handle_event("copied", _params, socket) do
    {:noreply, assign(socket, :copied, true)}
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
    socket = socket |> consume_all() |> put_cover_alt(all)
    attrs = normalize(params)

    case save(socket, attrs, all["intent"], schedule_time(all)) do
      {:ok, entry, message} ->
        socket =
          socket
          |> put_flash(:info, message)
          |> assign(
            entry: entry,
            now: DateTime.utc_now(),
            cover: entry.cover,
            pinned: entry.pinned_at != nil
          )
          |> assign_form(Entries.change(entry))
          |> assign_schedule(entry.published_at)
          |> assign_stats()

        if socket.assigns.live_action == :new do
          {:noreply, push_navigate(socket, to: ~m"/#{entry.id}")}
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
     |> push_navigate(to: ~m"/")}
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
      |> Map.new(fn {t, index} -> {Integer.to_string(index), translation_params(t)} end)

    field = &(Ecto.Changeset.get_field(changeset, &1) || &2)

    %{
      "slug" => field.(:slug, ""),
      "categories" => field.(:categories, []),
      "segments" => field.(:segments, []),
      "announce" => field.(:announce, ""),
      "announce_until" => field.(:announce_until, nil),
      "email" => field.(:email, false),
      "translations" => translations
    }
  end

  defp translation_params(t) do
    text =
      Map.new(
        ~w(title summary seo_title seo_description cta_label cta_url)a,
        &{to_string(&1), Map.get(t, &1) || ""}
      )

    Map.merge(text, %{
      "locale" => t.locale,
      "body" => if(t.body, do: JSON.encode!(t.body.doc), else: "")
    })
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
         {:ok, saved} <- put_cover(saved, socket.assigns.cover),
         {:ok, saved} <- put_pinned(saved, socket.assigns.pinned),
         {:ok, saved, message} <- apply_intent(saved, intent, at) do
      {:ok, Entries.get!(saved.id), message}
    end
  end

  # The cover's description is a field of the entry's form.
  defp put_cover_alt(%{assigns: %{cover: %{} = cover}} = socket, %{"cover_alt" => alt})
       when is_binary(alt),
       do: assign(socket, :cover, Map.put(cover, "alt", String.slice(alt, 0, 300)))

  defp put_cover_alt(socket, _params), do: socket

  defp put_cover(%Entry{cover: cover} = entry, cover), do: {:ok, entry}
  defp put_cover(entry, cover), do: Entries.put_cover_map(entry, cover)

  defp put_pinned(%Entry{pinned_at: nil} = entry, true), do: Entries.pin(entry)
  defp put_pinned(%Entry{pinned_at: %DateTime{}} = entry, false), do: Entries.unpin(entry)
  defp put_pinned(entry, _pinned), do: {:ok, entry}

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

  # The categories and segments are checkboxes, with an empty value so
  # that none checked is a value too.
  defp normalize(params) do
    params
    |> Map.put_new("categories", [])
    |> Map.put_new("segments", [])
  end

  defp consume_all(%{assigns: %{access: :all}} = socket) do
    Enum.reduce(socket.assigns.config.locales, socket, &consume(&2, &1))
  end

  defp consume_all(socket), do: socket

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
        read_only: assigns.access != :all,
        features: assigns.config.features,
        announce: Form.input_value(assigns.form, :announce),
        cover_upload: assigns[:uploads][:tayori_cover]
      )

    ~H"""
    <.page page={:entries} flash={@flash} access={@access} wide>
      <div class="ta-heading ta-editor-heading">
        <div class="ta-heading-title">
          <.link navigate={~m"/"} class="ta-icon-button" aria-label="Entries">
            <.icon name="arrow-left" />
          </.link>
          <h1>{if @entry.id, do: "Edit entry", else: "New entry"}</h1>
          <.status :if={@entry.id} entry={@entry} now={@now} />
        </div>
        <div class="ta-heading-actions">
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
          <button
            :if={@ai}
            type="button"
            class={["ta-button", @ai_open && "ta-pressed"]}
            phx-click="ai_toggle"
            aria-expanded={to_string(@ai_open)}
            aria-controls="ai-panel"
          >
            <.icon name="sparkles" />Write with AI
          </button>
        </div>
      </div>

      <section :if={@ai and @ai_open} id="ai-panel" class="ta-card ta-ai" aria-label="Write with AI">
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
              <.icon name="sparkles" />Draft in {Tayori.Locales.name(@language)}
            </button>
            <button
              :if={@language != hd(@config.locales)}
              type="button"
              class="ta-button"
              phx-click="ai_translate"
              disabled={@writers != %{}}
            >
              <.icon name="languages" />Translate from {Tayori.Locales.name(hd(@config.locales))}
            </button>
            <span :if={@writers != %{}} class="ta-hint ta-busy" role="status">
              <.icon name="loader-circle" class="ta-spin" />Writing…
            </span>
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
        class={["ta-editor", @mode == :preview && "ta-previewing"]}
      >
        <div class="ta-editor-main">
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
              <.icon name="plus" />{Tayori.Locales.name(locale)}
            </button>
          </div>

          <.preview
            :if={@mode == :preview}
            form={@form}
            entry={@entry}
            cover={@cover}
            pinned={@pinned}
            language={@language}
            categories={@categories}
            config={@config}
            preview_as={@preview_as}
          />

          <fieldset disabled={@read_only} class="ta-writing" hidden={@mode == :preview}>
            <.errors field={@form[:translations]} />

            <.inputs_for :let={t} field={@form[:translations]}>
              <section
                class="ta-translation"
                hidden={t[:locale].value != @language}
                aria-label={Tayori.Locales.name(t[:locale].value)}
              >
                <input type="hidden" name={t[:locale].name} value={t[:locale].value} />
                <div class="ta-field ta-title-field">
                  <label for={t[:title].id} class="ta-visually-hidden">Title</label>
                  <input
                    type="text"
                    id={t[:title].id}
                    name={t[:title].name}
                    value={t[:title].value}
                    maxlength="255"
                    placeholder="Title"
                    class="ta-title-input"
                    autocomplete="off"
                  />
                  <.errors field={t[:title]} />
                </div>
                <div class="ta-field ta-summary-field">
                  <label for={t[:summary].id} class="ta-visually-hidden">Summary</label>
                  <textarea
                    id={t[:summary].id}
                    name={t[:summary].name}
                    rows="2"
                    maxlength="500"
                    placeholder="A sentence or two for the panel, the cards and the emails"
                    class="ta-summary-input"
                  >{Form.normalize_value("textarea", t[:summary].value)}</textarea>
                  <.errors field={t[:summary]} />
                </div>
                <div class="ta-field ta-body-field">
                  <label id={"#{editor_id(t[:locale].value)}-label"} class="ta-visually-hidden">
                    Body
                  </label>
                  <Kotoba.Components.kotoba
                    id={editor_id(t[:locale].value)}
                    field={t[:body]}
                    label_id={"#{editor_id(t[:locale].value)}-label"}
                    features={Translation.features()}
                    uploads={assigns[:uploads][upload_name(@config.locales, t[:locale].value)]}
                    placeholder="What changed, and why it matters to your people. Drop screenshots in."
                    readonly={@read_only}
                    assist={if @ai, do: AI.actions()}
                  />
                </div>

                <details
                  :if={:announcements in @features and @announce not in [nil, ""]}
                  class="ta-more"
                  open
                >
                  <summary><.icon name="megaphone" />The announcement's button</summary>
                  <div class="ta-more-body ta-grid-2">
                    <.input
                      field={t[:cta_label]}
                      label="Label"
                      maxlength="80"
                      placeholder="Try it"
                    />
                    <.input
                      field={t[:cta_url]}
                      label="Address"
                      placeholder="/projects/new or https://…"
                      hint="A path of the app, or an https address."
                    />
                  </div>
                </details>

                <details class="ta-more">
                  <summary><.icon name="globe" />Search engines and shared links</summary>
                  <div class="ta-more-body">
                    <.input
                      field={t[:seo_title]}
                      label="Title"
                      maxlength="255"
                      hint="When not the entry's title."
                    />
                    <.input
                      field={t[:seo_description]}
                      type="textarea"
                      rows="2"
                      label="Description"
                      maxlength="500"
                      hint="When not the summary. About 150 characters show."
                    />
                  </div>
                </details>

                <label
                  :if={not @read_only and t[:locale].value != hd(@config.locales)}
                  class="ta-remove-language"
                >
                  <input
                    type="checkbox"
                    name="entry[translations_drop][]"
                    value={t.index}
                    class="ta-visually-hidden"
                  /><.icon name="trash-2" />Remove the {Tayori.Locales.name(t[:locale].value)} version
                </label>
              </section>
            </.inputs_for>
            <input type="hidden" name="entry[translations_drop][]" />
          </fieldset>
        </div>

        <aside class="ta-editor-side">
          <.card :if={not @read_only} title="Publication" icon="send" id="publication">
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
                <.icon name="send" />{publish_label(@schedule)}
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
            <div :if={@entry.id && @page_path} class="ta-links">
              <a
                :if={@status == :published}
                href={@page_path <> "/" <> @entry.slug}
                target="_blank"
                rel="noopener"
              >
                <.icon name="external-link" />View on the page
              </a>
              <button
                type="button"
                class="ta-link-button"
                id="preview-link"
                phx-hook="TayoriCopy"
                data-copy={preview_url(@socket, @page_path, @entry)}
                phx-click="copied"
              >
                <.icon name={if @copied, do: "check", else: "link"} />
                {if @copied, do: "Preview link copied", else: "Copy a preview link"}
              </button>
            </div>
            <p :if={@entry.id && @page_path} class="ta-hint">
              Anyone with the link sees the last saved version, for a week.
            </p>
          </.card>

          <.card title="Cover" icon="image" id="cover">
            <:aside>
              <span class="ta-optional">Optional</span>
            </:aside>
            <div :if={@cover} class="ta-cover">
              <img src={@cover["url"]} alt="" />
              <div :if={not @read_only} class="ta-cover-actions">
                <label class="ta-button ta-small" for={@cover_upload && @cover_upload.ref}>
                  <.icon name="refresh-cw" />Replace
                </label>
                <button type="button" class="ta-button ta-small ta-quiet" phx-click="remove_cover">
                  <.icon name="trash-2" />Remove
                </button>
              </div>
            </div>
            <label
              :if={!@cover and not @read_only}
              class="ta-dropzone"
              for={@cover_upload && @cover_upload.ref}
              phx-drop-target={@cover_upload && @cover_upload.ref}
            >
              <.icon name="upload" />
              <span><strong>Add a cover</strong> or drop an image here</span>
              <span class="ta-hint">At the top of the entry, on its card and on shared links. 16:9 looks best.</span>
            </label>
            <.live_file_input
              :if={@cover_upload}
              upload={@cover_upload}
              class="ta-visually-hidden"
            />
            <p
              :for={entry <- (@cover_upload && @cover_upload.entries) || []}
              class="ta-hint"
            >
              <.icon name="loader-circle" class="ta-spin" />Uploading {entry.client_name}… {entry.progress}%
            </p>
            <div :if={@cover && not @read_only} class="ta-field">
              <label for="cover-alt-input">Description</label>
              <input
                id="cover-alt-input"
                name="cover_alt"
                value={@cover["alt"]}
                class="ta-input"
                maxlength="300"
                placeholder="What the image shows, for those who cannot see it"
                phx-debounce="300"
              />
            </div>
          </.card>

          <.card title="Details" icon="tag" id="details">
            <fieldset disabled={@read_only}>
              <.input
                field={@form[:slug]}
                label="Address"
                hint="The end of its address on the public page. Made from the title when empty."
              />
              <div class="ta-field">
                <span class="ta-label">Categories</span>
                <input type="hidden" name="entry[categories][]" value="" />
                <div :if={@categories != []} class="ta-category-picks">
                  <label
                    :for={category <- @categories}
                    class="ta-category-pick"
                    data-color={category.color}
                  >
                    <input
                      type="checkbox"
                      name="entry[categories][]"
                      value={category.key}
                     
                      checked={category.key in (@form[:categories].value || [])}
                    />
                    <span class="tayori-dot"></span>
                    {Tayori.Category.name(category, nil, @config.locales)}
                  </label>
                </div>
                <p class="ta-hint">
                  <span :if={@categories == []}>No categories yet.</span>
                  <.link navigate={~m"/categories"}>Manage the categories</.link>
                </p>
              </div>
              <button
                type="button"
                class="ta-switch"
                role="switch"
                aria-checked={to_string(@pinned)}
                phx-click="pinned"
              >
                <span class="ta-switch-track"><span class="ta-switch-thumb"></span></span>
                <span>
                  <strong>Pin it</strong>
                  <span class="ta-hint">Pinned entries come first, in the app and on the page.</span>
                </span>
              </button>
            </fieldset>
          </.card>

          <.card title="Audience" icon="users" id="audience">
            <fieldset disabled={@read_only}>
              <p class="ta-audience-summary">
                <.icon name={if (@form[:segments].value || []) == [], do: "globe", else: "lock"} />
                <span>{audience_summary(@form[:segments].value || [], @segment_groups)}</span>
              </p>
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
              <p class="ta-hint ta-source">
                <span :if={@segment_groups != []}>
                  These groups come from your app: its <code>{inspect(@resolver)}.segments/0</code>,
                  and each reader's own from <code>resolve_reader/1</code>.
                </span>
                <span :if={@segment_groups == []}>
                  Every entry is for everyone. To write for some of your people (a plan, a role),
                  give <code>{inspect(@resolver)}</code> a <code>segments/0</code>.
                </span>
                <.link navigate={~m"/settings#audiences"}>How audiences work</.link>
              </p>
            </fieldset>
          </.card>

          <.card
            :if={:announcements in @features}
            title="Announcement"
            icon="megaphone"
            id="announcement"
          >
            <fieldset disabled={@read_only}>
              <div class="ta-choices" role="radiogroup" aria-label="Announce it as">
                <label
                  :for={
                    {value, label, icon} <- [
                      {"", "None", "x"},
                      {"popup", "Popup", "app-window"},
                      {"toast", "Toast", "message-square"},
                      {"banner", "Banner", "panel-top"}
                    ]
                  }
                  class="ta-choice"
                >
                  <input
                    type="radio"
                    name="entry[announce]"
                    value={value}
                   
                    checked={(@announce || "") == value}
                  />
                  <.icon name={icon} />{label}
                </label>
              </div>
              <div :if={@announce not in [nil, ""]} class="ta-field">
                <label id="announce-until-label">Until</label>
                <Koyomi.Components.datetime_picker
                  field={@form[:announce_until]}
                  label_id="announce-until-label"
                  time_zone={@time_zone}
                  locale={@locale}
                  rules={[min: :today]}
                />
                <p class="ta-hint">Empty: until the next announcement. Readers can dismiss it.</p>
              </div>
            </fieldset>
          </.card>

          <.card :if={:subscriptions in @features} title="Email" icon="mail" id="email">
            <fieldset disabled={@read_only or @entry.emailed_at != nil}>
              <input type="hidden" name="entry[email]" value="false" />
              <label class="ta-check">
                <input
                  type="checkbox"
                  name="entry[email]"
                  value="true"
                 
                  checked={Form.normalize_value("checkbox", @form[:email].value)}
                /> Send it to the subscribers when it is published
              </label>
              <p :if={@entry.emailed_at} class="ta-hint">
                Sent <.time at={@entry.emailed_at} />.
              </p>
              <p :if={(@form[:segments].value || []) != []} class="ta-hint ta-warning">
                <.icon name="info" />An entry for some readers is never emailed: subscribers are addresses, not readers.
              </p>
            </fieldset>
          </.card>

          <.card :if={@stats} title="Last 30 days" icon="chart-column" id="stats">
            <dl class="ta-stats">
              <div><dt>Views</dt><dd>{@stats.totals.views}</dd></div>
              <div><dt>Readers</dt><dd>{@stats.totals.readers}</dd></div>
            </dl>
            <div :if={length(@stats.days) > 1} class="ta-sparkline" aria-hidden="true">
              <span
                :for={{_date, sources} <- @stats.days}
                style={"--h: #{bar_height(sources, @stats.days)}"}
              >
              </span>
            </div>
            <ul class="ta-sources">
              <li :for={{source, n} <- Enum.sort_by(@stats.by_source, &(-elem(&1, 1)))}>
                <span>{source_label(source)}</span><span>{n}</span>
              </li>
            </ul>
          </.card>

          <section :if={@entry.id && not @read_only} class="ta-danger-zone">
            <button
              type="button"
              phx-click="delete"
              data-confirm="Delete this entry, in every language? This cannot be undone."
              class="ta-button ta-danger ta-quiet"
            >
              <.icon name="trash-2" />Delete entry
            </button>
          </section>
        </aside>
      </.form>
    </.page>
    """
  end

  attr :form, :any, required: true
  attr :entry, Entry, required: true
  attr :cover, :map, default: nil
  attr :pinned, :boolean, default: false
  attr :language, :string, required: true
  attr :categories, :list, required: true
  attr :config, :any, required: true
  attr :preview_as, :atom, required: true

  # The entry as it is in the form, as readers will see it.
  defp preview(assigns) do
    entry = preview_entry(assigns)
    messages = Messages.for_locale(assigns.language)
    categories = Map.new(assigns.categories, &{&1.key, &1})

    state = %Tayori.Live.State{
      open: true,
      entries: [entry],
      announcement: entry,
      categories: categories,
      messages: messages,
      locale: assigns.language,
      locales: assigns.config.locales,
      features: assigns.config.features,
      emoji: assigns.config.reactions
    }

    assigns =
      assign(assigns, preview: entry, messages: messages, map: categories, state: state)

    ~H"""
    <div class="ta-preview">
      <div class="ta-preview-bar">
        <div class="ta-segmented ta-small" role="tablist" aria-label="Preview as">
          <button
            :for={
              {as, label, icon} <- [
                {:page, "Page", "newspaper"},
                {:panel, "Panel", "panel-right"},
                {:announcement, "Announcement", "megaphone"}
              ]
            }
            :if={as != :announcement or :announcements in @config.features}
            type="button"
            role="tab"
            aria-selected={to_string(@preview_as == as)}
            phx-click="preview_as"
            phx-value-as={as}
          >
            <.icon name={icon} />{label}
          </button>
        </div>
        <span class="ta-hint">As your readers see it, in {Tayori.Locales.name(@language)}.</span>
      </div>

      <div :if={@preview_as == :page} class="ta-preview-stage tayori-page tayori-preview">
        <div class="tayori-shell">
          <article class="tayori-article">
            <Tayori.Components.entry
              entry={@preview}
              messages={@messages}
              categories={@map}
              locales={@config.locales}
              heading="h1"
            />
          </article>
        </div>
      </div>

      <div :if={@preview_as == :panel} class="ta-preview-stage ta-preview-panel tayori-preview">
        <div class="tayori-panel tayori-panel-static">
          <header class="tayori-panel-header">
            <h2>{@messages["title"]}</h2>
          </header>
          <div class="tayori-panel-body">
            <ol class="tayori-cards">
              <li>
                <Tayori.Components.card
                  entry={@preview}
                  messages={@messages}
                  categories={@map}
                  locales={@config.locales}
                  new
                />
              </li>
            </ol>
          </div>
        </div>
        <div class="tayori-panel tayori-panel-static">
          <header class="tayori-panel-header">
            <h2>{@messages["title"]}</h2>
          </header>
          <div class="tayori-panel-body">
            <Tayori.Components.entry
              entry={@preview}
              messages={@messages}
              categories={@map}
              locales={@config.locales}
            />
          </div>
        </div>
      </div>

      <div
        :if={@preview_as == :announcement}
        class="ta-preview-stage ta-preview-announcement tayori-preview"
      >
        <p :if={@preview.announce == nil} class="ta-hint">
          Choose how to announce it, in the Announcement card, to see it here.
        </p>
        <Tayori.Components.announcement :if={@preview.announce} tayori={@state} />
      </div>
    </div>
    """
  end

  defp preview_entry(assigns) do
    entry = Ecto.Changeset.apply_changes(assigns.form.source)

    translation =
      Enum.find(entry.translations, &(&1.locale == assigns.language)) ||
        List.first(entry.translations) || %Translation{title: ""}

    translation = %{
      translation
      | title: if(translation.title in [nil, ""], do: "Untitled", else: translation.title)
    }

    %{
      entry
      | translation: translation,
        cover: assigns.cover,
        pinned_at: if(assigns.pinned, do: DateTime.utc_now()),
        published_at: entry.published_at || DateTime.utc_now(),
        id: entry.id || "preview"
    }
  end

  defp preview_url(socket, page_path, %Entry{id: id}) when is_binary(id) do
    page_path <> "/preview/" <> Tayori.Page.preview_token(socket, id)
  end

  defp preview_url(_socket, _page_path, _entry), do: nil

  defp audience_summary([], _groups),
    do: "Everyone: in the app, on the public page and in the feeds."

  defp audience_summary(segments, groups) do
    labels =
      for {_group, list} <- groups, {segment, label} <- list, segment in segments, do: label

    "Only " <>
      Enum.join(labels, ", ") <>
      ", in the app. It is not on the public page, in the feeds or in the emails."
  end

  defp bar_height(sources, days) do
    max = days |> Enum.map(fn {_d, s} -> Enum.sum(Map.values(s)) end) |> Enum.max(fn -> 0 end)
    total = Enum.sum(Map.values(sources))
    if max == 0, do: "0%", else: "#{round(total / max * 100)}%"
  end

  defp source_label("panel"), do: "In the app"
  defp source_label("page"), do: "Public page"
  defp source_label("widget"), do: "Widget"
  defp source_label("email"), do: "Email"
  defp source_label("feed"), do: "Feeds"
  defp source_label(other), do: other

  defp present_locales(form) do
    form.source
    |> Ecto.Changeset.get_assoc(:translations, :struct)
    |> Enum.map(& &1.locale)
  end

  defp publish_label(schedule) do
    if schedule[:at].value in [nil, ""], do: "Publish now", else: "Schedule"
  end
end
