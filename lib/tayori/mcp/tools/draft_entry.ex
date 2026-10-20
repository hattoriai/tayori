if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.DraftEntry do
    @moduledoc false
    use Sake.Tool,
      name: "draft_entry",
      title: "Draft an entry from the inbox",
      description:
        "Make a draft entry of the inbox's new public changes, all of them or those given: " <>
          "one change makes an entry of its own, several an entry with a section for each " <>
          "category. The changes are then drafted. The entry is a draft: read it, improve " <>
          "it with update_entry, and publish it only when asked to.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: false]

    arg :change_ids, {:array, :string},
      description: "The changes to draft (list_changes); all the new public ones if not given"

    alias Tayori.{Config, Digest}
    alias Tayori.MCP.Support

    @impl true
    def execute(args, _ctx) do
      with {:ok, opts} <- ids(args[:change_ids]),
           {:ok, entry} <- run(opts) do
        {:ok,
         entry
         |> Support.entry_detail(Config.get())
         |> Map.put(:change_ids, Support.drafted_ids(entry))}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end

    defp ids(nil), do: {:ok, []}
    defp ids([]), do: {:error, "Give the ids of the changes, or none for all the new ones."}

    defp ids(ids) do
      with {:ok, ids} <- Support.change_ids(ids), do: {:ok, [ids: ids]}
    end

    # Always a draft, whatever the :digest config says.
    defp run(opts) do
      case Digest.run([publish: :draft] ++ opts) do
        {:ok, entry} ->
          {:ok, Tayori.Entries.get!(entry.id)}

        {:error, :nothing} ->
          {:error,
           "No change waits for an entry: none of the inbox's changes " <>
             if(opts == [], do: "is new and public.", else: "given is new and public.")}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end
end
