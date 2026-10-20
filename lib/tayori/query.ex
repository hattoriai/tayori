defmodule Tayori.Query do
  @moduledoc false
  # The queries of the news for a reader, on PostgreSQL and on SQLite: the
  # segments are an array in one and a JSON array in the other.

  import Ecto.Query

  alias Tayori.{Config, Entry, Reader}

  @doc "The entries a reader sees at a time: published, and for them."
  def visible(%Config{} = config, %Reader{} = reader, now) do
    from(e in Entry, as: :entry)
    |> where([e], not is_nil(e.published_at) and e.published_at <= ^now)
    |> for_segments(adapter(config), reader.segments)
  end

  @doc "The newest first, and the same order for the same time."
  def newest_first(query), do: order_by(query, [e], desc: e.published_at, desc: e.id)

  # An entry with no segments is for everyone; an entry with segments is
  # for the readers in one of them.
  defp for_segments(query, :postgres, []) do
    where(query, [e], fragment("cardinality(?) = 0", e.segments))
  end

  defp for_segments(query, :postgres, segments) do
    where(
      query,
      [e],
      fragment(
        "cardinality(?) = 0 OR ? && ?",
        e.segments,
        e.segments,
        type(^segments, {:array, :string})
      )
    )
  end

  defp for_segments(query, :sqlite, []) do
    where(query, [e], fragment("json_array_length(?) = 0", e.segments))
  end

  defp for_segments(query, :sqlite, segments) do
    where(
      query,
      [e],
      fragment(
        "json_array_length(?) = 0 OR EXISTS (SELECT 1 FROM json_each(?) AS s WHERE s.value IN (SELECT value FROM json_each(?)))",
        e.segments,
        e.segments,
        ^JSON.encode!(segments)
      )
    )
  end

  @doc false
  def adapter(%Config{repo: repo}) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.SQLite3 -> :sqlite
      other -> raise "Tayori runs on PostgreSQL and SQLite, not #{inspect(other)}"
    end
  end
end
