defmodule Tayori.Admin.SettingsLive do
  @moduledoc false
  # The settings of the admin: the AI model and its key (encrypted, never
  # shown again) and what the product is, for the drafts; the automation
  # (the inbox's sources, the digest, the ingest token and GitHub's
  # secret, each shown once); where the audiences come from; the extras of
  # the app; the subscribers; the webhooks, Slack and Discord; and the
  # embed on another domain.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Tayori.Admin.{Automation, InboxLive}
  alias Tayori.{AI, Config, Inbox, Resolver, Webhooks}

  # Suggestions only: any provider:model that ReqLLM knows will do.
  @models [
    "anthropic:claude-sonnet-5-5",
    "anthropic:claude-opus-5-5",
    "anthropic:claude-haiku-5-5"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Settings",
       models: @models,
       check: nil,
       segment_groups: Resolver.segment_groups(socket.assigns.resolver),
       new_secret: nil,
       tested: %{},
       embed_api: Automation.api_url(socket, :embed),
       machines_api: Automation.api_url(socket, :machines),
       embed_copied: false,
       copied: nil,
       reading: false,
       new_token: nil,
       new_github_secret: nil,
       sources: Automation.sources(socket.assigns.config)
     )
     |> load()}
  end

  defp load(socket) do
    settings = AI.settings()

    config = socket.assigns.config

    assign(socket,
      hooks: if(Config.feature?(config, :webhooks), do: Webhooks.list(), else: []),
      subscribers: if(Config.feature?(config, :subscriptions), do: Tayori.Subscribers.counts()),
      settings: settings,
      available: AI.available?(),
      last_read: Automation.last_read(),
      digest: Automation.digest_status(),
      pending: Inbox.pending_count(),
      token?: Automation.token?(),
      github_secret?: Automation.secret?(),
      form: to_form(%{"model" => settings.model, "about" => settings.about, "key" => ""}, as: :ai)
    )
  end

  @impl true
  def handle_event("save", %{"ai" => params}, %{assigns: %{access: :all}} = socket) do
    key =
      case String.trim(params["key"] || "") do
        "" -> :keep
        key -> key
      end

    :ok = AI.save_settings(params, key)

    {:noreply,
     socket |> put_flash(:info, "The settings are saved.") |> assign(check: nil) |> load()}
  end

  def handle_event("remove_key", _params, %{assigns: %{access: :all}} = socket) do
    :ok =
      AI.save_settings(
        %{
          "model" => socket.assigns.settings.model || "",
          "about" => socket.assigns.settings.about || ""
        },
        nil
      )

    {:noreply, socket |> put_flash(:info, "The key is removed.") |> assign(check: nil) |> load()}
  end

  def handle_event("check", _params, %{assigns: %{access: :all}} = socket) do
    {:noreply, socket |> assign(check: :checking) |> start_async(:check, &AI.check/0)}
  end

  def handle_event("add_hook", %{"hook" => hook}, %{assigns: %{access: :all}} = socket) do
    case Webhooks.add(hook["kind"] || "", hook["name"] || "", String.trim(hook["url"] || "")) do
      {:ok, secret} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{hook["name"]} is added.")
         |> assign(new_secret: secret)
         |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, hook_error(reason))}
    end
  end

  def handle_event("remove_hook", %{"id" => id}, %{assigns: %{access: :all}} = socket) do
    :ok = Webhooks.remove(id)
    {:noreply, socket |> put_flash(:info, "It is removed.") |> assign(new_secret: nil) |> load()}
  end

  def handle_event("test_hook", %{"id" => id}, %{assigns: %{access: :all}} = socket) do
    {:noreply,
     socket
     |> update(:tested, &Map.put(&1, id, :testing))
     |> start_async({:test_hook, id}, fn -> Webhooks.test(id) end)}
  end

  def handle_event("embed_copied", _params, socket),
    do: {:noreply, assign(socket, :embed_copied, true)}

  def handle_event("copied", %{"key" => key}, socket),
    do: {:noreply, assign(socket, :copied, key)}

  def handle_event("read", _params, %{assigns: %{access: :all}} = socket) do
    {:noreply, socket |> assign(reading: true) |> start_async(:read, &Automation.read_sources/0)}
  end

  def handle_event("new_token", _params, %{assigns: %{access: :all}} = socket) do
    {:ok, token} = Automation.new_token()

    {:noreply,
     socket
     |> put_flash(:info, "The token is made. Copy it now.")
     |> assign(new_token: token, copied: nil)
     |> load()}
  end

  def handle_event("revoke_token", _params, %{assigns: %{access: :all}} = socket) do
    :ok = Automation.revoke_token()

    {:noreply,
     socket
     |> put_flash(:info, "The token is revoked: it adds no change now.")
     |> assign(new_token: nil)
     |> load()}
  end

  def handle_event("new_github_secret", _params, %{assigns: %{access: :all}} = socket) do
    case Automation.new_secret() do
      {:ok, secret} ->
        {:noreply,
         socket
         |> put_flash(:info, "The secret is made. Copy it into GitHub now.")
         |> assign(new_github_secret: secret, copied: nil)
         |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, secret_error(reason))}
    end
  end

  def handle_event("remove_github_secret", _params, %{assigns: %{access: :all}} = socket) do
    :ok = Automation.remove_secret()

    {:noreply,
     socket
     |> put_flash(:info, "The secret is removed: GitHub's requests are refused.")
     |> assign(new_github_secret: nil)
     |> load()}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async({:test_hook, id}, {:ok, result}, socket),
    do: {:noreply, update(socket, :tested, &Map.put(&1, id, result))}

  def handle_async({:test_hook, id}, {:exit, reason}, socket),
    do: {:noreply, update(socket, :tested, &Map.put(&1, id, {:error, reason}))}

  def handle_async(:read, {:ok, results}, socket) do
    {:noreply,
     socket |> assign(reading: false) |> put_flash(:info, Automation.summary(results)) |> load()}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(reading: false)
     |> put_flash(:error, "The sources could not be read: #{inspect(reason)}")}
  end

  def handle_async(:check, {:ok, result}, socket), do: {:noreply, assign(socket, check: result)}

  def handle_async(:check, {:exit, reason}, socket),
    do: {:noreply, assign(socket, check: {:error, reason})}

  @impl true
  def render(assigns) do
    ~H"""
    <.page page={:settings} flash={@flash} access={@access} inbox={@inbox_new}>
      <div class="ta-heading">
        <div>
          <h1>Settings</h1>
          <p class="ta-subtitle">How Tayori writes, who reads, and where the news goes.</p>
        </div>
      </div>

      <div class="ta-settings">
        <nav class="ta-settings-nav" aria-label="Settings">
          <a href="#ai"><.icon name="sparkles" />Writing with AI</a>
          <a href="#automation"><.icon name="zap" />Automation</a>
          <a href="#audiences"><.icon name="users" />Audiences</a>
          <a href="#features"><.icon name="layers" />Features</a>
          <a :if={@subscribers} href="#email"><.icon name="mail" />Email</a>
          <a :if={:webhooks in @config.features} href="#integrations">
            <.icon name="webhook" />Integrations
          </a>
          <a href="#embed"><.icon name="code-xml" />Embed</a>
        </nav>

        <div class="ta-settings-body">
          <.card title="Writing with AI" icon="sparkles" id="ai">
            <p class="ta-lead">
              With a model and your own key, the editor drafts an entry from what shipped,
              translates it, and rewrites a passage. Every suggestion waits for you to accept it.
            </p>

            <div :if={not @available} class="ta-notice">
              <.icon name="info" />
              <div>
                <p :if={not Code.ensure_loaded?(ReqLLM)}>
                  AI needs ReqLLM in the app: add <code>{"{:req_llm, \"~> 1.6\"}"}</code> to the
                  dependencies.
                </p>
                <p :if={not Tayori.Settings.secrets?()}>
                  Tayori keeps the key encrypted: give it your Cloak vault (the
                  <code>:vault</code> option of Tayori), or the app's <code>secret_key_base</code>
                  (the <code>:secret_key_base</code> option).
                </p>
              </div>
            </div>

            <.form :if={@available} for={@form} id="ai-form" phx-submit="save">
              <fieldset disabled={@access != :all}>
                <div class="ta-grid-2">
                  <div class="ta-field">
                    <label for="ai_model">Model</label>
                    <input
                      type="text"
                      id="ai_model"
                      name="ai[model]"
                      value={@form[:model].value}
                      list="ai-models"
                      placeholder="anthropic:claude-sonnet-5-5"
                      autocomplete="off"
                      class="ta-input"
                    />
                    <datalist id="ai-models">
                      <option :for={model <- @models} value={model} />
                    </datalist>
                    <p class="ta-hint">The provider and the model, as ReqLLM names them.</p>
                  </div>

                  <div class="ta-field">
                    <label for="ai_key">API key</label>
                    <input
                      type="password"
                      id="ai_key"
                      name="ai[key]"
                      value=""
                      autocomplete="off"
                      placeholder={
                        if @settings.key?, do: "A key is saved. Type a new one to replace it.", else: "Your key"
                      }
                      class="ta-input"
                    />
                    <p class="ta-hint">Kept encrypted in your database, and never shown again.</p>
                  </div>
                </div>

                <div class="ta-field">
                  <label for="ai_about">About your product</label>
                  <textarea id="ai_about" name="ai[about]" rows="4" maxlength="2000" class="ta-input">{@form[:about].value}</textarea>
                  <p class="ta-hint">
                    What it is, who uses it, and how it speaks. Every draft starts from it.
                  </p>
                </div>

                <div class="ta-actions">
                  <button type="submit" class="ta-button ta-primary">Save</button>
                  <button
                    :if={@settings.key? and @settings.model not in [nil, ""]}
                    type="button"
                    class="ta-button"
                    phx-click="check"
                    disabled={@check == :checking}
                  >
                    <.icon :if={@check == :checking} name="loader-circle" class="ta-spin" />
                    {if @check == :checking, do: "Checking…", else: "Check the connection"}
                  </button>
                  <button
                    :if={@settings.key?}
                    type="button"
                    class="ta-button ta-quiet"
                    phx-click="remove_key"
                    data-confirm="Remove the key? The editor will have no AI until you give one."
                  >
                    Remove the key
                  </button>
                </div>
                <p :if={@check == :ok} class="ta-hint ta-ok" role="status">
                  <.icon name="circle-check" />The model answers.
                </p>
                <p :if={match?({:error, _}, @check)} class="ta-error" role="status">
                  The model did not answer: {error_text(@check)}
                </p>
              </fieldset>
            </.form>
          </.card>

          <.automation
            access={@access}
            config={@config}
            sources={@sources}
            last_read={@last_read}
            reading={@reading}
            digest={@digest}
            pending={@pending}
            api={@machines_api}
            token?={@token?}
            new_token={@new_token}
            github_secret?={@github_secret?}
            new_github_secret={@new_github_secret}
            copied={@copied}
          />

          <.card title="Audiences" icon="users" id="audiences">
            <p class="ta-lead">
              An entry is for everyone, or for some of your people: a plan, a role, a team.
              Tayori does not keep its own list of them. Your app knows who is on which plan,
              so it tells Tayori, in two functions of <code>{inspect(@resolver)}</code>:
            </p>
            <ol class="ta-steps">
              <li>
                <strong><code>segments/0</code></strong>
                lists the groups the editor offers, with their names.
              </li>
              <li>
                <strong><code>resolve_reader/1</code></strong>
                says which of them each reader is in, from your own user, on every request.
              </li>
            </ol>
            <p class="ta-hint">
              An entry for some readers is only in the app: never on the public page, in the
              feeds or in the emails. Change a user's plan in your app, and their news changes
              with it.
            </p>
            <div :if={@segment_groups != []} class="ta-segment-table">
              <div :for={{group, segments} <- @segment_groups} class="ta-segment-row">
                <span class="ta-segment-group">{group || "Groups"}</span>
                <span class="ta-segment-values">
                  <span :for={{key, label} <- segments} class="ta-tag" title={key}>
                    {label}<code>{key}</code>
                  </span>
                </span>
              </div>
            </div>
            <div :if={@segment_groups == []} class="ta-notice">
              <.icon name="info" />
              <p>
                No audiences yet: every entry is for everyone. Add <code>segments/0</code>
                and <code>resolve_reader/1</code> to <code>{inspect(@resolver)}</code> to write
                for some of your people.
              </p>
            </div>
          </.card>

          <.card title="Features" icon="layers" id="features">
            <p class="ta-lead">
              The changelog is always there. The extras are your app's choice, in the
              <code>:features</code> option of Tayori.
            </p>
            <ul class="ta-features">
              <li :for={{feature, {label, icon, text}} <- feature_labels()}>
                <span class="ta-feature-icon"><.icon name={icon} /></span>
                <span>
                  <strong>{label}</strong>
                  <span class="ta-hint">{text}</span>
                </span>
                <span class={["ta-badge", feature in @config.features && "ta-badge-on"]}>
                  {if feature in @config.features, do: "On", else: "Off"}
                </span>
              </li>
            </ul>
            <pre class="ta-code"><code>{"{Tayori,\n repo: MyApp.Repo,\n pubsub: MyApp.PubSub,\n features: [:reactions, :announcements, :analytics]}"}</code></pre>
          </.card>

          <.card :if={@subscribers} title="Email" icon="mail" id="email">
            <dl class="ta-stats">
              <div><dt>Subscribers</dt><dd>{@subscribers.confirmed}</dd></div>
              <div><dt>Waiting to confirm</dt><dd>{@subscribers.waiting}</dd></div>
            </dl>
            <p class="ta-hint">
              Readers subscribe on the public page and confirm their address. An entry is sent
              when it is published, if its Email box is checked and it is for everyone.
            </p>
          </.card>

          <.card :if={:webhooks in @config.features} title="Integrations" icon="webhook" id="integrations">
            <p class="ta-lead">
              Tell other places when an entry is published. Their addresses are kept encrypted.
            </p>
            <ul :if={@hooks != []} class="ta-hooks">
              <li :for={hook <- @hooks}>
                <span class="ta-feature-icon"><.icon name={if hook["kind"] == "webhook", do: "webhook", else: "message-square"} /></span>
                <span>
                  <strong>{hook["name"]}</strong>
                  <span class="ta-hint">{kind_label(hook["kind"])} · {hook["host"]}</span>
                </span>
                <span class="ta-row-actions">
                  <span :if={@tested[hook["id"]] == :ok} class="ta-hint ta-ok">
                    <.icon name="circle-check" />Delivered
                  </span>
                  <span :if={match?({:error, _}, @tested[hook["id"]])} class="ta-error">
                    Failed: {error_text(@tested[hook["id"]])}
                  </span>
                  <button
                    :if={@access == :all}
                    type="button"
                    class="ta-button ta-small"
                    phx-click="test_hook"
                    phx-value-id={hook["id"]}
                    disabled={@tested[hook["id"]] == :testing}
                  >
                    <.icon name="send" />Send a test
                  </button>
                  <button
                    :if={@access == :all}
                    type="button"
                    class="ta-icon-button"
                    phx-click="remove_hook"
                    phx-value-id={hook["id"]}
                    data-confirm="Remove it? It will not be told of new entries."
                    aria-label={"Remove #{hook["name"]}"}
                  >
                    <.icon name="trash-2" />
                  </button>
                </span>
              </li>
            </ul>
            <div :if={@new_secret} class="ta-notice">
              <.icon name="key-round" />
              <div>
                <p>
                  The webhook signs each request with this secret
                  (<code>x-tayori-signature: sha256=…</code>). Copy it now: it is not shown again.
                </p>
                <pre class="ta-code"><code>{@new_secret}</code></pre>
              </div>
            </div>
            <form :if={@access == :all} id="hook-form" phx-submit="add_hook" class="ta-hook-form">
              <div class="ta-field">
                <label for="hook-kind">Kind</label>
                <select id="hook-kind" name="hook[kind]" class="ta-input">
                  <option value="slack">Slack</option>
                  <option value="discord">Discord</option>
                  <option value="webhook">Webhook</option>
                </select>
              </div>
              <div class="ta-field">
                <label for="hook-name">Name</label>
                <input id="hook-name" name="hook[name]" class="ta-input" placeholder="#product" required />
              </div>
              <div class="ta-field ta-grow">
                <label for="hook-url">Address</label>
                <input
                  id="hook-url"
                  name="hook[url]"
                  type="url"
                  class="ta-input"
                  placeholder="https://hooks.slack.com/services/…"
                  required
                />
              </div>
              <button type="submit" class="ta-button ta-primary"><.icon name="plus" />Add</button>
            </form>
          </.card>

          <.card title="Embed" icon="code-xml" id="embed">
            <:aside>
              <span class={["ta-badge", :embed in @config.features && "ta-badge-on"]}>
                {if :embed in @config.features, do: "On", else: "Off"}
              </span>
            </:aside>
            <p class="ta-lead">
              The news on a site on another origin than the app's: a help centre, a marketing
              site. A script and an element read the news over the JSON API, with a token your
              server signs for the reader.
            </p>

            <div :if={:embed in @config.features}>
              <div class="ta-field">
                <span class="ta-label">The sites</span>
                <span class="ta-segment-values">
                  <span :for={origin <- @config.embed.origins} class="ta-tag">{origin}</span>
                </span>
                <p class="ta-hint">
                  The API answers their pages, and no others, and never with the app's cookies.
                  A reader token lasts {duration(@config.embed.max_age)}.
                </p>
              </div>

              <div :if={@embed_api} class="ta-field">
                <span class="ta-label">The snippet</span>
                <pre class="ta-code" id="embed-snippet"><code>{snippet(@embed_api)}</code></pre>
                <div class="ta-actions">
                  <button
                    type="button"
                    class="ta-button ta-small"
                    id="embed-copy"
                    phx-hook="TayoriCopy"
                    data-copy-text={snippet(@embed_api)}
                    phx-click="embed_copied"
                  >
                    <.icon name={if @embed_copied, do: "check", else: "copy"} />
                    {if @embed_copied, do: "Copied", else: "Copy the snippet"}
                  </button>
                </div>
                <p class="ta-hint">
                  The server that renders the page signs the token of the person it is for,
                  <code>Tayori.Embed.token(reader)</code>, with the reader your resolver gives.
                  Without <code>reader-token</code>, the page shows the news for everyone.
                </p>
              </div>

              <div :if={!@embed_api} class="ta-notice">
                <.icon name="info" />
                <p>
                  Mount the JSON API for the sites, behind a pipeline with no session:
                  <code>tayori_api "/news", resolver: {inspect(@resolver)}</code>.
                </p>
              </div>
            </div>

            <div :if={:embed not in @config.features}>
              <p class="ta-hint">
                Turn it on with the <code>:embed</code> feature, the origins of the sites, and the
                app's <code>secret_key_base</code>, which signs the reader tokens:
              </p>
              <pre class="ta-code"><code>{"{Tayori,\n repo: MyApp.Repo,\n pubsub: MyApp.PubSub,\n secret_key_base: secret_key_base,\n features: [:embed],\n embed: [origins: [\"https://www.example.com\"]]}"}</code></pre>
              <p class="ta-hint">Then mount the JSON API for the sites, as the Any frontend guide says.</p>
            </div>
          </.card>
        </div>
      </div>
    </.page>
    """
  end

  # The inbox's sources, the digest, and what the app's CI and GitHub
  # send: the ingest token and GitHub's secret, each shown once, when
  # Tayori has them.
  defp automation(assigns) do
    assigns =
      assign(assigns, :waiting, (assigns.digest && assigns.digest[:pending]) || assigns.pending)

    ~H"""
    <.card title="Automation" icon="zap" id="automation">
      <:aside>
        <.link navigate={~m"/inbox"} class="ta-button ta-small">
          <.icon name="inbox" />Open the inbox
        </.link>
      </:aside>
      <p class="ta-lead">
        What ships comes to the inbox: from your changelog and news fragments, your CI and
        GitHub. A digest makes an entry of what is new, for your people.
      </p>

      <section class="ta-subsection" aria-labelledby="automation-sources">
        <h3 id="automation-sources" class="ta-subheading">Sources</h3>
        <ul :if={@sources != []} class="ta-hooks">
          <li :for={source <- @sources}>
            <span class="ta-feature-icon"><.icon name={InboxLive.source_icon(source.name)} /></span>
            <span>
              <strong>{source.name}</strong>
              <span class="ta-hint">
                <code>{source.module}</code><span :if={source.path}> · {source.path}</span>
              </span>
            </span>
            <span
              :if={source_read(@last_read, source.name)}
              class={["ta-hint", source_read(@last_read, source.name)["error"] && "ta-error"]}
            >
              {Automation.counted(source_read(@last_read, source.name))}
            </span>
          </li>
        </ul>
        <div :if={@sources != []} class="ta-actions">
          <button
            :if={@access == :all}
            type="button"
            class="ta-button ta-small"
            phx-click="read"
            disabled={@reading}
          >
            <.icon name="refresh-cw" class={@reading && "ta-spin"} />
            {if @reading, do: "Reading…", else: "Read now"}
          </button>
          <span class="ta-hint">
            {if @config.inbox.ingest_on_start,
              do: "Read when the app starts, and when you ask.",
              else: "Read when you ask, and when your code calls Tayori.Inbox.ingest/0."}
            <span :if={@last_read}>Last read here <.time at={elem(@last_read, 0)} />.</span>
          </span>
        </div>
        <div :if={@sources == []}>
          <p class="ta-hint">
            No sources yet. Name them in the <code>:inbox</code> option of Tayori: a
            Keep a Changelog file, a folder of news fragments, or a module of your own.
          </p>
          <pre class="ta-code"><code>{inbox_sample()}</code></pre>
        </div>
      </section>

      <section class="ta-subsection" aria-labelledby="automation-digest">
        <h3 id="automation-digest" class="ta-subheading">Digest</h3>
        <dl class="ta-facts">
          <div><dt>When</dt><dd>{Automation.cadence(@config.digest)}</dd></div>
          <div>
            <dt>Then</dt>
            <dd>
              {if @config.digest.publish == :publish,
                do: "The entry is published at once.",
                else: "A draft, for you to read and publish."}
            </dd>
          </div>
          <div :if={@digest}>
            <dt>Next</dt>
            <dd>
              <.time :if={@digest[:next_run_at]} at={@digest.next_run_at} />
              <span :if={!@digest[:next_run_at]}>When you ask</span>
            </dd>
          </div>
          <div :if={@digest}>
            <dt>Last</dt>
            <dd>
              <.time :if={@digest[:last_run_at]} at={@digest.last_run_at} />
              <span :if={!@digest[:last_run_at]}>Never</span>
            </dd>
          </div>
          <div>
            <dt>Waiting</dt>
            <dd>
              {waiting(@waiting)}
              <.link :if={@waiting > 0} navigate={~m"/inbox"}>Draft an entry</.link>
            </dd>
          </div>
        </dl>
        <p class="ta-hint">
          The <code>:digest</code> option of Tayori sets them:
        </p>
        <pre class="ta-code"><code>{"digest: [every: {:weekly, :monday}, at: ~T[09:00:00], publish: :draft]"}</code></pre>
      </section>

      <section class="ta-subsection" aria-labelledby="automation-api">
        <h3 id="automation-api" class="ta-subheading">
          From your CI
          <span class={["ta-badge", @token? && "ta-badge-on"]}>
            {if @token?, do: "A token is set", else: "No token"}
          </span>
        </h3>
        <p class="ta-hint">
          A deploy, a release script or another service sends what shipped, with a token.
        </p>
        <.shown_once
          :if={@new_token}
          id="ingest-token"
          value={@new_token}
          copied={@copied == "token"}
          copy_key="token"
        >
          The token, for your CI's secrets. Copy it now: it is not shown again.
        </.shown_once>
        <div :if={@access == :all} class="ta-actions">
          <button :if={!@token?} type="button" class="ta-button ta-small" phx-click="new_token">
            <.icon name="key-round" />Create a token
          </button>
          <button
            :if={@token?}
            type="button"
            class="ta-button ta-small"
            phx-click="new_token"
            data-confirm="Replace the token? The one your CI has stops working."
          >
            <.icon name="refresh-cw" />Replace
          </button>
          <button
            :if={@token?}
            type="button"
            class="ta-button ta-quiet ta-small"
            phx-click="revoke_token"
            data-confirm="Revoke the token? Nothing adds changes with it after this."
          >
            Revoke
          </button>
        </div>
        <div :if={@api} class="ta-field">
          <span class="ta-label">The endpoint</span>
          <pre class="ta-code"><code>POST {@api}/changes</code></pre>
        </div>
        <div :if={@api} class="ta-field">
          <span class="ta-label">With curl</span>
          <pre class="ta-code" id="ingest-curl"><code>{curl(@api)}</code></pre>
          <div class="ta-actions">
            <button
              type="button"
              class="ta-button ta-small"
              id="ingest-curl-copy"
              phx-hook="TayoriCopy"
              data-copy-text={curl(@api)}
              phx-click="copied"
              phx-value-key="curl"
            >
              <.icon name={if @copied == "curl", do: "check", else: "copy"} />
              {if @copied == "curl", do: "Copied", else: "Copy"}
            </button>
          </div>
        </div>
        <.no_api :if={!@api} />
      </section>

      <section class="ta-subsection" aria-labelledby="automation-github">
        <h3 id="automation-github" class="ta-subheading">
          GitHub
          <span class={["ta-badge", @github_secret? && "ta-badge-on"]}>
            {if @github_secret?, do: "A secret is set", else: "No secret"}
          </span>
        </h3>
        <p class="ta-hint">
          A merged pull request or a published release comes to the inbox. In the
          repository's Settings → Webhooks, add a webhook with these:
        </p>
        <dl :if={@api} class="ta-facts">
          <div>
            <dt>Payload URL</dt>
            <dd>
              <code>{@api}/hooks/github</code>
              <button
                type="button"
                class="ta-icon-button"
                id="github-url-copy"
                phx-hook="TayoriCopy"
                data-copy-text={"#{@api}/hooks/github"}
                phx-click="copied"
                phx-value-key="github-url"
                aria-label="Copy the payload URL"
              >
                <.icon name={if @copied == "github-url", do: "check", else: "copy"} />
              </button>
            </dd>
          </div>
          <div><dt>Content type</dt><dd><code>application/json</code></dd></div>
          <div><dt>Secret</dt><dd>The one made here, shown once</dd></div>
          <div><dt>Events</dt><dd>Pull requests and releases</dd></div>
        </dl>
        <.no_api :if={!@api} />
        <.shown_once
          :if={@new_github_secret}
          id="github-secret"
          value={@new_github_secret}
          copied={@copied == "github-secret"}
          copy_key="github-secret"
        >
          The webhook's secret, for GitHub. Copy it now: it is not shown again.
        </.shown_once>
        <div :if={@access == :all} class="ta-actions">
          <button
            :if={!@github_secret?}
            type="button"
            class="ta-button ta-small"
            phx-click="new_github_secret"
          >
            <.icon name="key-round" />Create a secret
          </button>
          <button
            :if={@github_secret?}
            type="button"
            class="ta-button ta-small"
            phx-click="new_github_secret"
            data-confirm="Replace the secret? GitHub's requests are refused until it has the new one."
          >
            <.icon name="refresh-cw" />Replace
          </button>
          <button
            :if={@github_secret?}
            type="button"
            class="ta-button ta-quiet ta-small"
            phx-click="remove_github_secret"
            data-confirm="Remove the secret? GitHub's requests are refused after this."
          >
            Remove
          </button>
        </div>
      </section>
    </.card>
    """
  end

  defp no_api(assigns) do
    ~H"""
    <div class="ta-notice">
      <.icon name="info" />
      <p>
        Mount the JSON API for machines, behind a pipeline with no session and no CSRF
        protection, as the Automation guide says:
        <code>tayori_api "/news", resolver: …, as: :tayori_machines</code>.
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :copied, :boolean, default: false
  attr :copy_key, :string, required: true
  slot :inner_block, required: true

  # A token or a secret, shown once, with its copy button.
  defp shown_once(assigns) do
    ~H"""
    <div class="ta-notice ta-shown-once" id={@id}>
      <.icon name="key-round" />
      <div>
        <p>{render_slot(@inner_block)}</p>
        <div class="ta-secret">
          <pre class="ta-code"><code>{@value}</code></pre>
          <button
            type="button"
            class="ta-button ta-small"
            id={"#{@id}-copy"}
            phx-hook="TayoriCopy"
            data-copy-text={@value}
            phx-click="copied"
            phx-value-key={@copy_key}
          >
            <.icon name={if @copied, do: "check", else: "copy"} />
            {if @copied, do: "Copied", else: "Copy"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # What the admin's "Read now" gave a source, as kept.
  defp source_read(nil, _name), do: nil
  defp source_read({_at, sources}, name), do: sources[name]

  defp inbox_sample do
    """
    {Tayori,
     repo: MyApp.Repo,
     pubsub: MyApp.PubSub,
     inbox: [
       sources: [
         {Tayori.Sources.Changelog, path: {:my_app, "priv/CHANGELOG.md"}},
         {Tayori.Sources.Fragments, path: {:my_app, "priv/news"}}
       ]
     ]}\
    """
  end

  defp curl(api) do
    """
    curl -X POST #{api}/changes \\
      -H "authorization: Bearer $TAYORI_INGEST_TOKEN" \\
      -H "content-type: application/json" \\
      -d '{"changes": [{"ref": "pr-1234", "title": "Exports in two clicks", "kind": "added"}]}'\
    """
  end

  defp waiting(0), do: "Nothing new for the public"
  defp waiting(1), do: "1 new change for the public"
  defp waiting(n), do: "#{n} new changes for the public"

  defp secret_error(:no_secrets),
    do: "Tayori keeps it encrypted: give it a :vault or a :secret_key_base."

  defp snippet(api) do
    """
    <link rel="stylesheet" href="#{api}/tayori.css" />
    <script type="module" src="#{api}/tayori.js"></script>

    <tayori-news api="#{api}" reader-token="<%= Tayori.Embed.token(@reader) %>"></tayori-news>\
    """
  end

  defp duration(seconds) when rem(seconds, 86_400) == 0,
    do: plural(div(seconds, 86_400), "a day", "days")

  defp duration(seconds) when rem(seconds, 3600) == 0,
    do: plural(div(seconds, 3600), "an hour", "hours")

  defp duration(seconds) when rem(seconds, 60) == 0,
    do: plural(div(seconds, 60), "a minute", "minutes")

  defp duration(seconds), do: plural(seconds, "a second", "seconds")

  defp plural(1, one, _other), do: one
  defp plural(n, _one, other), do: "#{n} #{other}"

  defp error_text({:error, %{__exception__: true} = error}), do: Exception.message(error)
  defp error_text({:error, reason}) when is_binary(reason), do: reason
  defp error_text({:error, reason}), do: inspect(reason)

  defp hook_error(:no_secrets),
    do: "Tayori keeps their addresses encrypted: give it a :vault or a :secret_key_base."

  defp hook_error(:not_https), do: "The address must start with https://."
  defp hook_error(:no_name), do: "Give it a name."
  defp hook_error(_reason), do: "It could not be added."

  defp kind_label("webhook"), do: "Webhook"
  defp kind_label("slack"), do: "Slack"
  defp kind_label("discord"), do: "Discord"

  @feature_labels [
    reactions: {"Reactions", "smile-plus", "Readers react to an entry with an emoji."},
    announcements:
      {"Announcements", "megaphone", "An entry as a popup, a toast or a banner in the app."},
    analytics: {"Analytics", "chart-column", "The views of each entry, and where it was read."},
    subscriptions: {"Email", "mail", "Readers subscribe on the page; entries are sent to them."},
    webhooks: {"Integrations", "webhook", "Webhooks, Slack and Discord, told of each entry."},
    embed: {"Embed", "code-xml", "The news on another domain than the app's."}
  ]

  defp feature_labels, do: @feature_labels
end
