defmodule Tayori.Admin.SettingsLive do
  @moduledoc false
  # The settings of the admin: the AI model and its key (encrypted, never
  # shown again), and what the product is, for the drafts.

  use Phoenix.LiveView, layout: false

  import Tayori.Admin.Components

  alias Tayori.AI

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
     |> assign(page_title: "Settings", models: @models, check: nil)
     |> load()}
  end

  defp load(socket) do
    settings = AI.settings()

    assign(socket,
      settings: settings,
      available: AI.available?(),
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

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:check, {:ok, result}, socket), do: {:noreply, assign(socket, check: result)}

  def handle_async(:check, {:exit, reason}, socket),
    do: {:noreply, assign(socket, check: {:error, reason})}

  @impl true
  def render(assigns) do
    ~H"""
    <.page prefix={@prefix} page={:settings} flash={@flash}>
      <div class="ta-toolbar">
        <h1>Settings</h1>
      </div>

      <section class="ta-panel ta-settings" aria-labelledby="ai-heading">
        <h2 id="ai-heading">Writing with AI</h2>
        <p class="ta-hint">
          With a model and your own key, the editor drafts an entry from what shipped,
          translates it, and rewrites a passage. Every suggestion waits for you to accept it.
        </p>

        <div :if={not @available} class="ta-notice">
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

        <.form :if={@available} for={@form} id="ai-form" phx-submit="save">
          <fieldset disabled={@access != :all}>
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
                placeholder={if @settings.key?, do: "A key is saved. Type a new one to replace it.", else: "Your key"}
                class="ta-input"
              />
              <p class="ta-hint">
                Kept encrypted in your database, and never shown again.
              </p>
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
            <p :if={@check == :ok} class="ta-hint ta-ok" role="status">The model answers.</p>
            <p :if={match?({:error, _}, @check)} class="ta-error" role="status">
              The model did not answer: {error_text(@check)}
            </p>
          </fieldset>
        </.form>
      </section>
    </.page>
    """
  end

  defp error_text({:error, %{__exception__: true} = error}), do: Exception.message(error)
  defp error_text({:error, reason}) when is_binary(reason), do: reason
  defp error_text({:error, reason}), do: inspect(reason)
end
