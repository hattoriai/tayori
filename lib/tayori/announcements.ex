defmodule Tayori.Announcements do
  @moduledoc """
  An entry announced in the app, as a popup, a toast or a banner, until
  its date (`Tayori.Entry`'s `:announce`): the `:announcements` feature.

  A reader sees one announcement at a time, the newest they can see and
  have not dismissed. A visitor sees it until the page closes it.
  """

  import Ecto.Query

  alias Tayori.{Config, Entry, Query, Reader}

  @doc """
  The announcement the reader sees now, with its translation, or nil.
  Always nil when the `:announcements` feature is off.
  """
  @spec current(Reader.t(), keyword()) :: Entry.t() | nil
  def current(%Reader{} = reader, opts \\ []) do
    config = Config.get()
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    if Config.feature?(config, :announcements) do
      config
      |> Query.visible(reader, now)
      |> where([e], not is_nil(e.announce))
      |> where([e], is_nil(e.announce_until) or e.announce_until > ^now)
      |> not_dismissed(reader)
      |> Query.newest_first()
      |> limit(1)
      |> config.repo.all(prefix: config.prefix)
      |> Tayori.with_translations(config, reader)
      |> List.first()
    end
  end

  defp not_dismissed(query, %Reader{id: nil}), do: query

  defp not_dismissed(query, %Reader{id: id}) do
    where(
      query,
      [e],
      e.id not in subquery(
        from(d in "tayori_dismissals",
          where: d.reader == ^id,
          select: type(d.entry_id, :binary_id)
        )
      )
    )
  end

  @doc """
  Dismisses an announcement for the reader, on every device. Does nothing
  for a visitor.
  """
  @spec dismiss(Reader.t(), Ecto.UUID.t()) :: :ok
  def dismiss(%Reader{id: nil}, _entry_id), do: :ok

  def dismiss(%Reader{id: id}, entry_id) do
    config = Config.get()

    config.repo.insert_all(
      "tayori_dismissals",
      [%{reader: id, entry_id: Ecto.UUID.dump!(entry_id), inserted_at: DateTime.utc_now()}],
      on_conflict: :nothing,
      prefix: config.prefix
    )

    Tayori.broadcast_reader(id, {Tayori, :dismissed, entry_id})
    :ok
  end
end
