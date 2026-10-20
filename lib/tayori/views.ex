defmodule Tayori.Views do
  @moduledoc """
  The views of the entries, by day and by where they were read: the
  `:analytics` feature.

  A reader's views are counted under their id; a visitor's under no one,
  with the other visitors of the day. Nothing else is kept: no address, no
  device, no cookie.

  The sources are `"panel"` (the app's news panel), `"page"` (the public
  page), `"widget"` (`<tayori-news>`), `"email"` and `"feed"`.
  """

  import Ecto.Query

  alias Tayori.{Config, Reader, View}

  @sources ~w(panel page widget email feed)

  @doc "The places an entry can be read."
  @spec sources() :: [String.t()]
  def sources, do: @sources

  @doc """
  Counts a view of an entry by a reader, from a source. Does nothing when
  the `:analytics` feature is off.
  """
  @spec track(Reader.t() | nil, Ecto.UUID.t(), String.t()) :: :ok
  def track(reader, entry_id, source) when source in @sources do
    config = Config.get()

    if Config.feature?(config, :analytics) do
      row = %{
        entry_id: entry_id,
        reader: (reader && reader.id) || "",
        source: source,
        day: Date.utc_today(),
        count: 1
      }

      config.repo.insert_all(View, [row],
        on_conflict: [inc: [count: 1]],
        conflict_target: [:entry_id, :reader, :source, :day],
        prefix: config.prefix
      )
    end

    :ok
  end

  @doc """
  The views and readers of each entry, `%{entry_id => %{views: n, readers: n}}`:
  every view, and the readers who viewed it at least once (visitors not
  counted).
  """
  @spec totals([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => %{views: integer(), readers: integer()}}
  def totals([]), do: %{}

  def totals(entry_ids) do
    config = Config.get()

    from(v in View,
      where: v.entry_id in ^entry_ids,
      group_by: v.entry_id,
      select: {v.entry_id, sum(v.count), fragment("COUNT(DISTINCT NULLIF(?, ''))", v.reader)}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Map.new(fn {id, views, readers} -> {id, %{views: views || 0, readers: readers}} end)
  end

  @doc """
  An entry's views by day and by source, since a day: a list of
  `{date, %{source => n}}`, the oldest first, with every day.
  """
  @spec by_day(Ecto.UUID.t(), Date.t()) :: [{Date.t(), %{String.t() => integer()}}]
  def by_day(entry_id, since) do
    config = Config.get()

    rows =
      from(v in View,
        where: v.entry_id == ^entry_id and v.day >= ^since,
        group_by: [v.day, v.source],
        select: {v.day, v.source, sum(v.count)}
      )
      |> config.repo.all(prefix: config.prefix)
      |> Enum.group_by(&day(elem(&1, 0)), fn {_day, source, n} -> {source, n} end)

    for date <- Date.range(since, Date.utc_today()),
        do: {date, Map.new(Map.get(rows, date, []))}
  end

  defp day(%Date{} = date), do: date
  defp day(text) when is_binary(text), do: Date.from_iso8601!(text)
end
