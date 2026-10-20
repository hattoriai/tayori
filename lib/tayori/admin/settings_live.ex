defmodule Tayori.Admin.SettingsLive do
  @moduledoc false
  # The settings of the admin.

  use Phoenix.LiveView, layout: false

  import Tayori.Admin.Components

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page prefix={@prefix} page={:settings} flash={@flash}>
      <div class="ta-toolbar">
        <h1>Settings</h1>
      </div>
    </.page>
    """
  end
end
