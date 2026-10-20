defmodule Tayori.Digest do
  @moduledoc """
  An entry made of the inbox's changes (`Tayori.Inbox`): the changes
  waiting, for the public, put in an entry for the people who use the app.

      {:ok, entry} = Tayori.Digest.run()
      {:ok, entry} = Tayori.Digest.run(ids: ["0193…", "0194…"])

  The entry is a draft for the admin to read and publish, unless the
  `:digest` config says `publish: :publish`; the changes it takes are
  then `"drafted"`, with the entry's id. A change for the team only
  (`audience: "internal"`), or put aside, never goes into one.

  ## Written by the model, or plain

  When the admin has set up AI (`Tayori.AI.configured?/0`), the model
  writes the entry from the changes: a title, a summary and a body, in
  the first language and the product's voice, the highlights first. It
  gets each change's title, body, category and highlight, never its ref,
  link or author, and never a change for the team. With
  `digest: [translate: true]`, it also translates the entry into the
  other languages. When the model fails, the digest is plain, and a
  warning is logged.

  A plain digest, without AI or with `ai: false`: one change makes an
  entry of its own, its title and its body; several make an entry titled
  with the day, with a section for each category, the highlighted first.

  The entry's categories and segments are always the changes', not the
  model's.

  ## When

  The `:every` of the `:digest` config: `:manual`, when the admin asks;
  `:ingest`, each time changes come (`after_ingest/1`); or a schedule,
  which Tayori's scheduler keeps (`next_run/3`). A scheduled digest with
  fewer changes than `:minimum` makes nothing, and its changes wait for
  the next time. With the `:oban` option, it runs in a job of
  `Tayori.Worker`; without, in a task. `status/0` says where it stands.
  """

  alias Tayori.{AI, Categories, Category, Config, Entries, Inbox, Jobs, Messages, Settings}

  require Logger

  @setting "digest"

  @doc """
  Makes an entry of the changes waiting. Options:

    * `:ids` - these changes only (still only the new, public ones).
    * `:since`, `:until` - the changes that happened in this time.
    * `:publish` - `:draft` or `:publish`, instead of the config's.
    * `:ai` - `false` for a plain digest, even with AI set up.
    * `:now` - the time of the digest (now).
    * `:author` - the entry's author, as the resolver's `author/1` gives it.

  Returns `{:ok, entry}`, `{:error, :nothing}` when no change is
  waiting, or `{:error, changeset}`.
  """
  @spec run(keyword()) :: {:ok, Tayori.Entry.t()} | {:error, :nothing | Ecto.Changeset.t()}
  def run(opts \\ []) do
    config = Config.get()

    case Inbox.pending(Keyword.take(opts, [:ids, :since, :until])) do
      [] ->
        {:error, :nothing}

      changes ->
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
        publish = Keyword.get(opts, :publish, config.digest.publish)
        ai? = Keyword.get(opts, :ai, true) != false and AI.configured?()

        with {:ok, entry} <- create(changes, config, now, ai?, opts),
             {:ok, entry} <- maybe_publish(entry, publish, now) do
          Inbox.drafted(Enum.map(changes, & &1.id), entry.id)
          {:ok, entry}
        end
    end
  end

  # An entry the model wrote that the entry refuses is made plain.
  defp create(changes, config, now, true, opts) do
    case Entries.create(attrs(changes, config, now, true), Keyword.take(opts, [:author])) do
      {:ok, entry} ->
        {:ok, entry}

      {:error, changeset} ->
        Logger.warning(
          "Tayori made the digest plain, the model's was refused: #{inspect(changeset.errors)}"
        )

        create(changes, config, now, false, opts)
    end
  end

  defp create(changes, config, now, false, opts),
    do: Entries.create(attrs(changes, config, now, false), Keyword.take(opts, [:author]))

  defp maybe_publish(entry, :publish, now), do: Entries.publish(entry, now)
  defp maybe_publish(entry, _draft, _now), do: {:ok, entry}

  @doc false
  # The entry of the changes: its text in the first language, written by
  # the model or plain, and its translations when the config asks.
  @spec attrs([Tayori.Change.t()], Config.t(), DateTime.t(), boolean()) :: map()
  def attrs(changes, config, now, ai? \\ false) do
    locale = Config.default_locale(config)

    {text, translations} =
      with true <- ai?,
           {:ok, text} <- written(changes, locale) do
        {text, translations(text, locale, config)}
      else
        false ->
          {text(changes, locale, config, now), []}

        {:error, reason} ->
          Logger.warning(
            "Tayori's model did not write the digest, which is plain: #{inspect(reason)}"
          )

          {text(changes, locale, config, now), []}
      end

    %{
      categories: changes |> Enum.map(& &1.category) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      segments: segments(changes),
      translations: [translation(locale, text) | translations]
    }
  end

  defp translation(locale, {title, summary, markdown}) do
    %{
      locale: locale,
      title: title,
      summary: summary,
      body: Kotoba.Content.from_markdown(markdown)
    }
  end

  # The entry as the model writes it.
  defp written(changes, locale) do
    with {:ok, reply} <- AI.complete({:digest, changes, locale}), do: read_reply(reply)
  end

  # The other languages, each translated from the first; one the model
  # fails is left for the admin.
  defp translations({title, summary, markdown}, from, config) do
    if config.digest.translate do
      for to <- config.locales -- [from],
          text = %{title: title, summary: summary || "", markdown: markdown},
          {:ok, text} <- [translated(text, from, to)],
          do: translation(to, text)
    else
      []
    end
  end

  defp translated(text, from, to) do
    with {:ok, reply} <- AI.complete({:translate, text, from, to}),
         {:ok, text} <- read_reply(reply) do
      {:ok, text}
    else
      {:error, reason} ->
        Logger.warning(
          "Tayori's model did not translate the digest into #{to}: #{inspect(reason)}"
        )

        :error
    end
  end

  # A title, a summary and a body, as long as an entry takes them.
  defp read_reply(reply) do
    case AI.parse_header(String.trim_leading(reply)) do
      {:ok, %{title: title, summary: summary}, body} when title not in [nil, ""] ->
        summary = if summary in [nil, ""], do: nil, else: String.slice(summary, 0, 500)
        {:ok, {String.slice(title, 0, 255), summary, String.trim(body)}}

      _other ->
        {:error, :unreadable}
    end
  end

  defp text([change], _locale, _config, _now) do
    {change.title, nil, change.body || ""}
  end

  defp text(changes, locale, config, now) do
    categories = Categories.by_key()
    messages = Messages.for_locale(locale)

    sections =
      changes
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {key, _} -> position(categories, key) end)
      |> Enum.map_join("\n\n", fn {key, changes} ->
        heading(categories, key, locale, config) <> Enum.map_join(changes, "\n", &item/1)
      end)

    {Messages.date(messages, now), nil, sections}
  end

  defp heading(_categories, nil, _locale, _config), do: ""

  defp heading(categories, key, locale, config) do
    case categories[key] do
      %Category{} = category -> "## " <> Category.name(category, locale, config.locales) <> "\n\n"
      nil -> ""
    end
  end

  defp position(_categories, nil), do: {1, 0}

  defp position(categories, key) do
    case categories[key] do
      %Category{position: position} -> {0, position}
      nil -> {1, 0}
    end
  end

  defp item(change) do
    title = if change.highlight, do: "**#{change.title}**", else: change.title

    case change.body do
      body when is_binary(body) and body != "" ->
        "- #{title}: " <> (body |> String.replace(~r/\s*\n\s*/, " ") |> trim_title(change.title))

      _ ->
        "- #{title}"
    end
  end

  # A body that starts with its title says it once.
  defp trim_title(body, title) do
    if String.starts_with?(body, title),
      do: body |> String.replace_prefix(title, "") |> String.replace(~r/^[\s.:,;—–-]+/u, ""),
      else: body
  end

  # An entry is for every reader unless all its changes are for some.
  defp segments(changes) do
    if Enum.all?(changes, &(&1.segments != [])),
      do: changes |> Enum.flat_map(& &1.segments) |> Enum.uniq(),
      else: []
  end

  # -- when ---------------------------------------------------------------

  @typedoc "A schedule: the `:every` and `:at` of the `:digest` or `:emails` config."
  @type schedule :: %{
          required(:every) => term(),
          required(:at) => Time.t(),
          optional(atom()) => term()
        }

  @doc """
  The time of the next scheduled run, after the last one (or after
  `now`, when there was none), or nil when the schedule has no time:

    * `{:weekly, day}` - the first such day after the last run, at `:at`;
    * `:monthly` - the first day of the month after the last run, at `:at`;
    * `{:days, n}` - n days after the day of the last run, at `:at`;
    * `:manual`, `:ingest` (and the `:each` of `:emails`) - nil.

  A time that is past is due: a run missed while the app was down is
  made once, at the next look.

  ## Examples

      iex> schedule = %{every: {:weekly, :monday}, at: ~T[09:00:00]}
      iex> Tayori.Digest.next_run(schedule, ~U[2026-10-19 09:00:30Z], ~U[2026-10-20 12:00:00Z])
      ~U[2026-10-26 09:00:00Z]

      iex> schedule = %{every: :monthly, at: ~T[09:00:00]}
      iex> Tayori.Digest.next_run(schedule, nil, ~U[2026-10-20 12:00:00Z])
      ~U[2026-11-01 09:00:00Z]

      iex> Tayori.Digest.next_run(%{every: :manual, at: ~T[09:00:00]}, nil, ~U[2026-10-20 12:00:00Z])
      nil

  """
  @spec next_run(schedule(), DateTime.t() | nil, DateTime.t()) :: DateTime.t() | nil
  def next_run(%{every: every, at: at}, last_run_at, now) do
    from = last_run_at || now

    case every do
      {:weekly, day} -> first_after(from, at, &(Date.day_of_week(&1) == weekday(day)))
      :monthly -> first_after(from, at, &(&1.day == 1))
      {:days, n} -> DateTime.new!(Date.add(DateTime.to_date(from), n), at, "Etc/UTC")
      _no_time -> nil
    end
  end

  # The first day at a time after a moment, among those that pass a test
  # (no more than a month and a day ahead).
  defp first_after(from, at, day?) do
    from
    |> DateTime.to_date()
    |> Stream.iterate(&Date.add(&1, 1))
    |> Stream.take(33)
    |> Stream.filter(day?)
    |> Stream.map(&DateTime.new!(&1, at, "Etc/UTC"))
    |> Enum.find(&(DateTime.compare(&1, from) == :gt))
  end

  @doc false
  # Whether a schedule has times of its own.
  @spec timed?(schedule()) :: boolean()
  def timed?(%{every: every}), do: every == :monthly or is_tuple(every)

  @weekdays %{
    monday: 1,
    tuesday: 2,
    wednesday: 3,
    thursday: 4,
    friday: 5,
    saturday: 6,
    sunday: 7
  }

  defp weekday(day), do: Map.fetch!(@weekdays, day)

  @doc """
  Whether the scheduled digest of the config is due at a time: its
  `next_run/3` after the last one has come.
  """
  @spec due?(Config.t(), DateTime.t()) :: boolean()
  def due?(%Config{} = config \\ Config.get(), now \\ DateTime.utc_now()) do
    case next_run(config.digest, last_run(@setting, now), now) do
      nil -> false
      at -> DateTime.compare(at, now) != :gt
    end
  end

  @doc """
  Where the digest stands, for the admin: its `:every`, the time of the
  next scheduled one (nil for `:manual` and `:ingest`), the last
  scheduled one (nil before the first), and how many changes wait.
  """
  @spec status() :: %{
          every: term(),
          next_run_at: DateTime.t() | nil,
          last_run_at: DateTime.t() | nil,
          pending: non_neg_integer()
        }
  def status do
    config = Config.get()
    now = DateTime.utc_now()

    %{
      every: config.digest.every,
      next_run_at: next_run(config.digest, last_run(@setting, now), now),
      last_run_at: ran_at(@setting),
      pending: length(Inbox.pending())
    }
  end

  @doc """
  Tells the digest that changes came: with `every: :ingest`, a digest
  runs when at least one is new. `Tayori.Inbox.ingest/0` calls it, and
  so does whatever else adds changes in batches, with the count of new
  ones.
  """
  @spec after_ingest(non_neg_integer()) :: :ok
  def after_ingest(added) when is_integer(added) and added > 0 do
    config = Config.get()

    if config.digest.every == :ingest do
      record(@setting, DateTime.utc_now())
      Jobs.digest(config)
    end

    :ok
  end

  def after_ingest(_added), do: :ok

  @doc false
  # From the scheduler: starts the digest when its time has come. The run
  # is recorded first, so that the next look does not start it again.
  @spec tick(Config.t(), DateTime.t()) :: :ok
  def tick(%Config{} = config, now) do
    if timed?(config.digest) do
      begin(@setting, now)

      if due?(config, now) do
        record(@setting, now)
        Jobs.digest(config)
      end
    end

    :ok
  end

  @doc false
  # The digest of a schedule, in its job or task: nothing when fewer
  # changes than the config's minimum wait.
  @spec scheduled() :: {:ok, Tayori.Entry.t()} | {:error, :nothing | Ecto.Changeset.t()}
  def scheduled do
    config = Config.get()

    if length(Inbox.pending()) < config.digest.minimum,
      do: {:error, :nothing},
      else: run()
  end

  # The time of a schedule's last run, kept in a setting, or the time it
  # began: a schedule's first run is its first time after Tayori starts.

  @doc false
  @spec last_run(String.t(), DateTime.t()) :: DateTime.t()
  def last_run(setting, now) do
    value = Settings.get(setting)
    time(value["last_run_at"]) || time(value["since"]) || now
  end

  @doc false
  @spec ran_at(String.t()) :: DateTime.t() | nil
  def ran_at(setting), do: time(Settings.get(setting)["last_run_at"])

  @doc false
  @spec record(String.t(), DateTime.t()) :: :ok
  def record(setting, now) do
    Settings.put(setting, Map.put(Settings.get(setting), "last_run_at", DateTime.to_iso8601(now)))
  end

  @doc false
  @spec began(String.t()) :: DateTime.t() | nil
  def began(setting), do: time(Settings.get(setting)["since"])

  @doc false
  @spec begin(String.t(), DateTime.t()) :: :ok
  def begin(setting, now) do
    value = Settings.get(setting)

    if value["since"] || value["last_run_at"],
      do: :ok,
      else: Settings.put(setting, Map.put(value, "since", DateTime.to_iso8601(now)))
  end

  defp time(nil), do: nil

  defp time(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      _error -> nil
    end
  end
end
