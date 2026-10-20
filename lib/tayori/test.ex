defmodule Tayori.Test do
  @moduledoc """
  Helpers for `Phoenix.LiveViewTest`, to test the news in an app's
  LiveViews with no browser: write entries, read the count of unread
  entries, open the panel and read it.

      import Tayori.Test

      test "a Pro customer sees the news for Pro", %{conn: conn} do
        publish!("Shared boards", segments: ["plan:pro"])
        publish!("Faster search")

        {:ok, view, _html} = conn |> log_in(pro_user()) |> live(~p"/projects")

        assert unread(view) == 2
        assert [%{title: "Shared boards", new: true}, %{title: "Faster search"}] = open_news(view)
        assert unread(view) == 0
      end

  The entries are written in the app's test database, through
  `Tayori.Entries`, so Tayori must be in the app's supervision tree in the
  tests too (it is when the app starts).
  """

  @compile {:no_warn_undefined, [LazyHTML]}

  import ExUnit.Assertions

  alias Phoenix.LiveViewTest

  @doc """
  Writes and publishes an entry, in the first language. Options:

    * `:body` - Markdown (`"About <title>."`);
    * `:categories`, `:segments` - lists of strings;
    * `:at` - the publication time (now), a time in the future schedules it;
    * `:translations` - other languages, `%{"pt-PT" => "Título"}` or
      `%{"pt-PT" => {"Título", "Corpo"}}`.
  """
  @spec publish!(String.t(), keyword()) :: Tayori.Entry.t()
  def publish!(title, opts \\ []) do
    config = Tayori.Config.get()
    [first | _] = config.locales

    others =
      for {locale, value} <- Keyword.get(opts, :translations, %{}) do
        {title, body} = if is_tuple(value), do: value, else: {value, nil}
        %{locale: locale, title: title, body: Kotoba.Content.from_markdown(body || "")}
      end

    body = Keyword.get(opts, :body, "About #{title}.")

    {:ok, entry} =
      Tayori.Entries.create(%{
        categories: Keyword.get(opts, :categories, []),
        segments: Keyword.get(opts, :segments, []),
        translations: [
          %{locale: first, title: title, body: Kotoba.Content.from_markdown(body)} | others
        ]
      })

    {:ok, entry} = Tayori.Entries.publish(entry, Keyword.get_lazy(opts, :at, &DateTime.utc_now/0))
    Tayori.broadcast({Tayori, :published, entry.id})
    entry
  end

  @doc """
  The count of unread entries that the button of a LiveView shows (0 when
  it shows none).
  """
  @spec unread(LiveViewTest.View.t() | Phoenix.LiveViewTest.Element.t()) :: non_neg_integer()
  def unread(view) do
    case view
         |> html()
         |> LazyHTML.query(".tayori-button .tayori-badge")
         |> Enum.map(&LazyHTML.text/1) do
      [] -> 0
      ["9+"] -> 10
      [count] -> count |> String.trim() |> String.to_integer()
    end
  end

  @doc """
  Opens the panel of a LiveView, as a click on its button does, and
  returns its entries (`entries/1`). It marks the news as seen.
  """
  @spec open_news(LiveViewTest.View.t()) :: [map()]
  def open_news(view) do
    assert LiveViewTest.has_element?(view, ".tayori-button"),
           "Tayori.Test: the LiveView has no news button (Tayori.Components.news_button/1)"

    view |> LiveViewTest.element(".tayori-button") |> LiveViewTest.render_click()
    entries(view)
  end

  @doc """
  The entries the panel of a LiveView shows, in order: each with its
  `:title`, `:categories`, and whether it is marked `:new`.
  """
  @spec entries(LiveViewTest.View.t()) :: [
          %{title: String.t(), categories: [String.t()], new: boolean()}
        ]
  def entries(view) do
    view
    |> html()
    |> LazyHTML.query("#tayori-panel .tayori-entry")
    |> Enum.map(fn entry ->
      %{
        title: entry |> LazyHTML.query(".tayori-entry-title") |> LazyHTML.text() |> String.trim(),
        categories:
          entry |> LazyHTML.query(".tayori-category") |> Enum.map(&String.trim(LazyHTML.text(&1))),
        new: entry |> LazyHTML.query(".tayori-new") |> Enum.any?()
      }
    end)
  end

  @doc "Closes the panel of a LiveView."
  @spec close_news(LiveViewTest.View.t()) :: :ok
  def close_news(view) do
    view |> LiveViewTest.element("#tayori-panel .tayori-close") |> LiveViewTest.render_click()
    :ok
  end

  defp html(view), do: view |> LiveViewTest.render() |> LazyHTML.from_fragment()
end
