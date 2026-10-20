defmodule Tayori.Admin.CategoriesLive do
  @moduledoc false
  # The categories of the news: their names in each language, their
  # colours and their order. A category removed is taken off its entries.

  use Phoenix.LiveView, layout: false
  use PhoenixMountable.Path, mountable: Tayori.Router

  import Tayori.Admin.Components

  alias Tayori.{Categories, Category, Entries}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tayori.subscribe()

    {:ok,
     socket
     |> assign(page_title: "Categories", editing: nil)
     |> load()}
  end

  defp load(socket) do
    counts =
      Entries.list()
      |> Enum.flat_map(& &1.categories)
      |> Enum.frequencies()

    assign(socket, categories: Categories.list(), counts: counts)
  end

  @impl true
  def handle_event("new", _params, %{assigns: %{access: :all}} = socket) do
    {:noreply, edit(socket, :new, %Category{color: next_color(socket.assigns.categories)})}
  end

  def handle_event("edit", %{"key" => key}, %{assigns: %{access: :all}} = socket) do
    case Categories.get(key) do
      nil -> {:noreply, socket}
      category -> {:noreply, edit(socket, key, category)}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, editing: nil)}
  end

  def handle_event("validate", %{"category" => params}, socket) do
    changeset =
      socket.assigns.category
      |> Categories.change(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :category))}
  end

  def handle_event("save", %{"category" => params}, %{assigns: %{access: :all}} = socket) do
    result =
      case socket.assigns.editing do
        :new -> Categories.create(params)
        _key -> Categories.update(socket.assigns.category, params)
      end

    case result do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "“#{Category.name(category, nil, socket.assigns.config.locales)}” is saved."
         )
         |> assign(editing: nil)
         |> load()}

      {:error, changeset} ->
        {:noreply,
         assign(socket, form: to_form(Map.put(changeset, :action, :insert), as: :category))}
    end
  end

  def handle_event("delete", %{"key" => key}, %{assigns: %{access: :all}} = socket) do
    with %Category{} = category <- Categories.get(key),
         {:ok, _} <- Categories.delete(category) do
      {:noreply,
       socket |> put_flash(:info, "The category is deleted.") |> assign(editing: nil) |> load()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move", %{"key" => key, "by" => by}, %{assigns: %{access: :all}} = socket) do
    keys = Enum.map(socket.assigns.categories, & &1.key)
    index = Enum.find_index(keys, &(&1 == key))
    to = index && index + if(by == "up", do: -1, else: 1)

    if index && to >= 0 && to < length(keys) do
      keys = keys |> List.delete_at(index) |> List.insert_at(to, key)
      :ok = Categories.reorder(keys)
      {:noreply, load(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({Tayori, event, _key}, socket) when event in [:categories, :changed],
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp edit(socket, editing, category) do
    assign(socket,
      editing: editing,
      category: category,
      form: to_form(Categories.change(category), as: :category)
    )
  end

  # Its names in the languages after the first, for the list.
  defp other_names(category, [_first | others]) do
    others |> Enum.map(&category.names[&1]) |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  # A new category takes the next colour not yet used.
  defp next_color(categories) do
    used = Enum.map(categories, & &1.color)
    Enum.find(Category.colors() -- ["gray"], "gray", &(&1 not in used))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page page={:categories} flash={@flash} access={@access} inbox={@inbox_new}>
      <div class="ta-heading">
        <div>
          <h1>Categories</h1>
          <p class="ta-subtitle">
            What kind of news an entry is: readers filter by them, in the app and on the page.
          </p>
        </div>
        <button
          :if={@access == :all and @editing != :new}
          type="button"
          class="ta-button"
          phx-click="new"
        >
          <.icon name="plus" />New category
        </button>
      </div>

      <.category_form :if={@editing == :new} form={@form} config={@config} new />

      <ol :if={@categories != []} class="ta-categories">
        <li :for={{category, index} <- Enum.with_index(@categories)} id={"category-#{category.key}"}>
          <.category_form
            :if={@editing == category.key}
            form={@form}
            config={@config}
            key={category.key}
          />
          <div :if={@editing != category.key} class="ta-category-row">
            <span class="ta-category-swatch" data-color={category.color}></span>
            <span class="ta-category-names">
              <span
                class="tayori-category"
                data-color={category.color}
              >
                {Category.name(category, nil, @config.locales)}
              </span>
              <span :if={length(@config.locales) > 1} class="ta-hint">
                {other_names(category, @config.locales)}
              </span>
            </span>
            <span class="ta-category-count">
              {Map.get(@counts, category.key, 0)} {if Map.get(@counts, category.key, 0) == 1,
                do: "entry",
                else: "entries"}
            </span>
            <span :if={@access == :all} class="ta-row-actions">
              <button
                type="button"
                class="ta-icon-button"
                phx-click="move"
                phx-value-key={category.key}
                phx-value-by="up"
                disabled={index == 0}
                aria-label={"Move #{category.key} up"}
              >
                <.icon name="chevron-up" />
              </button>
              <button
                type="button"
                class="ta-icon-button"
                phx-click="move"
                phx-value-key={category.key}
                phx-value-by="down"
                disabled={index == length(@categories) - 1}
                aria-label={"Move #{category.key} down"}
              >
                <.icon name="chevron-down" />
              </button>
              <button
                type="button"
                class="ta-icon-button"
                phx-click="edit"
                phx-value-key={category.key}
                aria-label={"Edit #{category.key}"}
              >
                <.icon name="pencil" />
              </button>
            </span>
          </div>
        </li>
      </ol>

      <.empty :if={@categories == [] and @editing == nil} icon="tags" title="No categories yet">
        <p>New, Improved, Fixed: name the kinds of news you write, in each language.</p>
        <button :if={@access == :all} type="button" class="ta-button ta-primary" phx-click="new">
          <.icon name="plus" />Add the first category
        </button>
      </.empty>
    </.page>
    """
  end

  attr :form, :any, required: true
  attr :config, :any, required: true
  attr :new, :boolean, default: false
  attr :key, :string, default: nil

  defp category_form(assigns) do
    ~H"""
    <.form for={@form} id="category-form" class="ta-card ta-category-form" phx-change="validate" phx-submit="save">
      <div class="ta-grid-2">
        <div :for={locale <- @config.locales} class="ta-field">
          <label for={"category-name-#{locale}"}>
            Name<span :if={length(@config.locales) > 1}> in {Tayori.Locales.name(locale)}</span>
          </label>
          <input
            id={"category-name-#{locale}"}
            name={"category[names][#{locale}]"}
            value={(@form[:names].value || %{})[locale]}
            class="ta-input"
            maxlength="60"
            placeholder={if locale == hd(@config.locales), do: "Improved", else: "Optional"}
            autofocus={locale == hd(@config.locales)}
          />
        </div>
      </div>
      <.errors field={@form[:names]} />
      <div class="ta-field">
        <span class="ta-label">Colour</span>
        <div class="ta-swatches" role="radiogroup" aria-label="Colour">
          <label :for={color <- Tayori.Category.colors()} class="ta-swatch" data-color={color} title={color}>
            <input
              type="radio"
              name="category[color]"
              value={color}
              checked={@form[:color].value == color}
              class="ta-visually-hidden"
            />
            <span aria-hidden="true"></span>
            <span class="ta-visually-hidden">{color}</span>
          </label>
        </div>
      </div>
      <.input
        :if={@new}
        field={@form[:key]}
        label="Key"
        hint="How the API, the feeds and ?category= name it. Made from the name when empty; it stays."
      />
      <.errors :if={!@new} field={@form[:key]} />
      <div class="ta-actions">
        <button type="submit" class="ta-button ta-primary">{if @new, do: "Add category", else: "Save"}</button>
        <button type="button" class="ta-button ta-quiet" phx-click="cancel">Cancel</button>
        <button
          :if={!@new}
          type="button"
          class="ta-button ta-danger ta-quiet ta-push"
          phx-click="delete"
          phx-value-key={@key}
          data-confirm="Delete this category? The entries keep everything else."
        >
          <.icon name="trash-2" />Delete
        </button>
      </div>
    </.form>
    """
  end
end
