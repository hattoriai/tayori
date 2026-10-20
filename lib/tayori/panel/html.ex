defmodule Tayori.Panel.HTML do
  @moduledoc false
  # The panel's components as HTML, for <tayori-news>: the button, the
  # panel and the announcement of Tayori.Components, rendered from the
  # same state as in a LiveView. The element answers their phx-click and
  # phx-value-* itself, so a page without LiveView gets the same markup.

  use Phoenix.Component

  alias Phoenix.HTML.Safe
  alias Tayori.Components
  alias Tayori.Live.State

  @doc false
  @spec button(State.t(), boolean()) :: String.t()
  def button(%State{} = state, label?) do
    assigns = %{tayori: state, label: label?}
    to_html(~H"<Components.news_button tayori={@tayori} label={@label} />")
  end

  @doc false
  @spec panel(State.t()) :: String.t()
  def panel(%State{} = state) do
    assigns = %{tayori: state}
    to_html(~H"<Components.news_panel tayori={@tayori} />")
  end

  @doc false
  @spec announcement(State.t()) :: String.t()
  def announcement(%State{} = state) do
    assigns = %{tayori: state}
    to_html(~H"<Components.announcement tayori={@tayori} />")
  end

  defp to_html(rendered) do
    rendered |> Safe.to_iodata() |> IO.iodata_to_binary() |> String.trim()
  end
end
