defmodule Tayori.Reactions do
  @moduledoc """
  Readers react to an entry with an emoji, one of the app's (`:reactions`
  of `Tayori.Config`), and each reaction counts once per reader. The
  `:reactions` feature.

  A visitor (a reader with no id) cannot react: a reaction is a reader's,
  so that a count is people, not clicks.
  """

  import Ecto.Query

  alias Tayori.{Config, Reaction, Reader}

  @doc """
  Turns a reaction of the reader on or off, and returns the entry's counts
  and the reader's reactions. An emoji that is not one of the app's is
  refused.
  """
  @spec toggle(Reader.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, %{counts: map(), mine: [String.t()]}} | {:error, :visitor | :unknown_emoji}
  def toggle(%Reader{id: nil}, _entry_id, _emoji), do: {:error, :visitor}

  def toggle(%Reader{id: reader}, entry_id, emoji) do
    config = Config.get()

    cond do
      emoji not in config.reactions ->
        {:error, :unknown_emoji}

      mine(config, reader, [entry_id]) |> Map.get(entry_id, []) |> Enum.member?(emoji) ->
        from(r in Reaction,
          where: r.entry_id == ^entry_id and r.reader == ^reader,
          where: r.emoji == ^emoji
        )
        |> config.repo.delete_all(prefix: config.prefix)

        reacted(config, reader, entry_id)

      true ->
        config.repo.insert_all(
          Reaction,
          [
            %{
              entry_id: entry_id,
              reader: reader,
              emoji: emoji,
              inserted_at: DateTime.utc_now()
            }
          ],
          on_conflict: :nothing,
          prefix: config.prefix
        )

        reacted(config, reader, entry_id)
    end
  end

  defp reacted(config, reader, entry_id) do
    Tayori.broadcast({Tayori, :reacted, entry_id})

    {:ok,
     %{
       counts: Map.get(counts(config, [entry_id]), entry_id, %{}),
       mine: Map.get(mine(config, reader, [entry_id]), entry_id, [])
     }}
  end

  @doc """
  The counts of each emoji of the entries, `%{entry_id => %{emoji => n}}`,
  and the reader's own reactions, `%{entry_id => [emoji]}`.
  """
  @spec for_entries(Reader.t(), [Ecto.UUID.t()]) :: {map(), map()}
  def for_entries(_reader, []), do: {%{}, %{}}

  def for_entries(%Reader{id: reader}, entry_ids) do
    config = Config.get()
    {counts(config, entry_ids), if(reader, do: mine(config, reader, entry_ids), else: %{})}
  end

  defp counts(config, entry_ids) do
    from(r in Reaction,
      where: r.entry_id in ^entry_ids,
      group_by: [r.entry_id, r.emoji],
      select: {r.entry_id, r.emoji, count()}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Enum.group_by(&elem(&1, 0), fn {_id, emoji, n} -> {emoji, n} end)
    |> Map.new(fn {id, pairs} -> {id, Map.new(pairs)} end)
  end

  defp mine(config, reader, entry_ids) do
    from(r in Reaction,
      where: r.entry_id in ^entry_ids and r.reader == ^reader,
      order_by: r.inserted_at,
      select: {r.entry_id, r.emoji}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "The number of reactions of each entry, for the admin."
  @spec totals([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => non_neg_integer()}
  def totals([]), do: %{}

  def totals(entry_ids) do
    config = Config.get()

    from(r in Reaction,
      where: r.entry_id in ^entry_ids,
      group_by: r.entry_id,
      select: {r.entry_id, count()}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Map.new()
  end
end
