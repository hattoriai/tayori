defmodule Tayori.Admin.Components do
  @moduledoc false
  # The small pieces of the admin's pages.

  use Phoenix.Component

  alias Tayori.Entry

  defdelegate page(assigns), to: Tayori.Admin.Layouts

  attr :entry, Entry, required: true
  attr :now, DateTime, required: true

  @doc "The status of an entry, with its time in the admin's own time zone."
  def status(assigns) do
    assigns = assign(assigns, :status, Entry.status(assigns.entry, assigns.now))

    ~H"""
    <span class={"ta-status ta-status-#{@status}"}>
      <%= case @status do %>
        <% :draft -> %>
          Draft
        <% :scheduled -> %>
          Scheduled for <.time at={@entry.published_at} />
        <% :published -> %>
          Published <.time at={@entry.published_at} />
      <% end %>
    </span>
    """
  end

  attr :at, DateTime, required: true

  @doc """
  A time, written in UTC and shown by the admin's script in the admin's
  own time zone and language.
  """
  def time(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@at)} data-tayori-time>
      {Calendar.strftime(@at, "%d %b %Y, %H:%M UTC")}
    </time>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :hint, :string, default: nil
  attr :rest, :global, include: ~w(disabled placeholder rows maxlength autocomplete)

  @doc "A labelled input with its errors."
  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="ta-field">
      <label for={@field.id}>{@label}</label>
      <textarea id={@field.id} name={@field.name} class="ta-input" {@rest}>{Phoenix.HTML.Form.normalize_value("textarea", @field.value)}</textarea>
      <p :if={@hint} class="ta-hint">{@hint}</p>
      <.errors field={@field} />
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="ta-field">
      <label for={@field.id}>{@label}</label>
      <input
        type={@type}
        id={@field.id}
        name={@field.name}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        class="ta-input"
        {@rest}
      />
      <p :if={@hint} class="ta-hint">{@hint}</p>
      <.errors field={@field} />
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  @doc "The errors of a field, once the person has touched it."
  def errors(assigns) do
    assigns =
      assign(
        assigns,
        :errors,
        if(Phoenix.Component.used_input?(assigns.field), do: assigns.field.errors, else: [])
      )

    ~H"""
    <p :for={error <- @errors} class="ta-error">{translate_error(error)}</p>
    """
  end

  @doc false
  def translate_error({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
