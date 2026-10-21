defmodule Tayori.Test do
  @moduledoc """
  Helpers for `Phoenix.LiveViewTest`, to test the news in an app's
  LiveViews with no browser: write entries, read the count of unread
  entries, open the panel and read it.

      import Tayori.Test

      test "a Pro customer sees the news for Pro", %{conn: conn} do
        publish!("Faster search")
        publish!("Shared boards", segments: ["plan:pro"])

        {:ok, view, _html} = conn |> log_in(pro_user()) |> live(~p"/projects")

        assert unread(view) == 2
        assert [%{title: "Shared boards", new: true}, %{title: "Faster search"}] = open_news(view)
        assert unread(view) == 0
      end

  The entries are written in the app's test database, through
  `Tayori.Entries`, so Tayori must be in the app's supervision tree in the
  tests too (it is when the app starts).

  ## Campaigns

  With the `:campaigns` module, a test tracks what a person did, then
  runs the campaigns at a time of its own, and reads the letters with
  `Swoosh.TestAssertions`:

      import Swoosh.TestAssertions

      test "the welcome, then the tips two days later" do
        user = user_fixture()
        now = DateTime.utc_now()

        track!("user:\#{user.id}", "signed_up", at: now)
        run_campaigns!(now)
        assert_email_sent(subject: "Welcome to Atelier")

        run_campaigns!(DateTime.add(now, 2, :day))
        assert_email_sent(subject: "Three things to try")
      end

    * `track!/3` - an event, as `Tayori.track/3`, at a time (`:at`).
    * `run_campaigns!/2` - what is due at a time: the people of the
      sequences whose time came are advanced, the broadcasts whose time
      came are sent, and their letters go through the app's mailer, in
      the test's process, with or without Oban.
    * `post_webhook!/2` - a mail provider's payload, as if the provider
      had posted it (its signature aside): a bounce, a complaint.
  """

  @compile {:no_warn_undefined, [LazyHTML]}

  import ExUnit.Assertions

  alias Phoenix.LiveViewTest
  alias Tayori.Campaigns.{Runner, Webhooks}

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
  Announces the entries whose time has come, as Tayori's scheduler does,
  in the test's process: the app's notifier is called, the subscribers
  emailed and the webhooks told, or, with the `:oban` option, their jobs
  enqueued. Each entry is announced once.

      entry = publish!("Exports")
      announce!()
      assert_enqueued worker: Tayori.Worker, args: %{"job" => "notify", "entry_id" => entry.id}
  """
  @spec announce!() :: :ok
  def announce! do
    Tayori.Scheduler.announce_due(Tayori.Config.get())
    :ok
  end

  @doc """
  The count of unread entries that the button of a LiveView shows (0 when
  it shows none).
  """
  @spec unread(struct()) :: non_neg_integer()
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
  @spec open_news(struct()) :: [map()]
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
  @spec entries(struct()) :: [
          %{title: String.t(), categories: [String.t()], new: boolean()}
        ]
  def entries(view) do
    view
    |> html()
    |> LazyHTML.query("#tayori-panel .tayori-card")
    |> Enum.map(fn entry ->
      %{
        title: entry |> LazyHTML.query(".tayori-card-title") |> LazyHTML.text() |> String.trim(),
        categories:
          entry |> LazyHTML.query(".tayori-category") |> Enum.map(&String.trim(LazyHTML.text(&1))),
        new: entry |> LazyHTML.query(".tayori-new") |> Enum.any?()
      }
    end)
  end

  @doc "Closes the panel of a LiveView."
  @spec close_news(struct()) :: :ok
  def close_news(view) do
    view |> LiveViewTest.element("#tayori-panel .tayori-close") |> LiveViewTest.render_click()
    :ok
  end

  defp html(view), do: view |> LiveViewTest.render() |> LazyHTML.from_fragment()

  # ── Campaigns ───────────────────────────────────────────────────

  @doc """
  Tracks an event of a person, as `Tayori.track/3`: the active sequences
  it triggers take them in. Options: `:meta`, `:at` (now). Raises without
  the `:campaigns` module.
  """
  @spec track!(String.t(), String.t(), keyword()) :: :ok
  def track!(person_id, name, opts \\ []) do
    campaigns!()
    :ok = Tayori.track(person_id, name, opts)
  end

  @doc """
  Runs the campaigns at a time (now), in the test's process: each person
  whose time came is advanced, and gets the letters due then; each
  broadcast whose time came is sent. The letters go through the app's
  mailer at once, with or without Oban, so that `Swoosh.TestAssertions`
  sees them.

  Options: `:batch_size` - the people of a broadcast read at a time
  (500).

      run_campaigns!(DateTime.add(signed_up_at, 2, :day))
      assert_email_sent(subject: "Your first project")
  """
  @spec run_campaigns!(DateTime.t(), keyword()) :: :ok
  def run_campaigns!(at \\ DateTime.utc_now(), opts \\ []) do
    config = campaigns!()
    opts = Keyword.take(opts, [:batch_size]) ++ [inline: true, resume: true]
    Runner.run_due(%{config | oban: nil}, at, opts)
  end

  @doc """
  Hands a payload to a mail provider of the `:providers` of `:campaigns`
  (`:resend`, `:postmark` or the app's own), as if the provider had
  posted it to its webhook, its signature aside: a hard bounce or a
  complaint suppresses the address. Returns how many events it had.

      post_webhook!(:resend, %{
        "type" => "email.bounced",
        "data" => %{"email_id" => "re_1", "to" => ["ada@example.com"]}
      })

      assert Tayori.Campaigns.suppressed?("ada@example.com", :product)
  """
  @spec post_webhook!(atom() | String.t(), map()) :: non_neg_integer()
  def post_webhook!(provider, payload) when is_map(payload) do
    config = campaigns!()

    case Webhooks.provider(config, to_string(provider)) do
      {module, _opts} ->
        Webhooks.handle(config, module, payload)

      nil ->
        raise ArgumentError,
              "Tayori.Test: #{inspect(provider)} is not in the :providers of :campaigns"
    end
  end

  defp campaigns! do
    config = Tayori.Config.get()

    unless Tayori.Config.module?(config, :campaigns) do
      raise ArgumentError, "Tayori.Test: the :campaigns module is off"
    end

    config
  end
end
