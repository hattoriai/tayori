if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.AddChange do
    @moduledoc false
    use Sake.Tool,
      name: "add_change",
      title: "Add a change to the inbox",
      description:
        "Add a change that shipped to the inbox, for a later entry: what changed for the " <>
          "app's people, in their words. With a ref, adding it again changes nothing. " <>
          "A change for the team only (audience internal) never goes into an entry.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: false]

    arg :title, :string, required: true, max_length: 255, description: "What changed, in a line"
    arg :body, :string, max_length: 20_000, description: "More about it, in Markdown"

    arg :kind, :string,
      max_length: 32,
      description: "Its kind (\"added\", \"fixed\", \"improved\"), which may give its category"

    arg :category, :string,
      max_length: 64,
      description: "The key of its category (list_categories)"

    arg :audience, {:enum, ["public", "internal"]},
      description: "public (the default) for the readers, internal for the team only"

    arg :segments, {:array, :string},
      description: "The readers it is for, when not everyone (the app's segments)"

    arg :highlight, :boolean, description: "Worth leading an entry with"
    arg :version, :string, max_length: 64, description: "The version it shipped in"
    arg :url, :string, max_length: 2048, description: "A link to it, such as a pull request"

    arg :ref, :string,
      max_length: 255,
      description:
        "Its name where it comes from (a pull request, a commit); one is made if not given"

    alias Tayori.Inbox
    alias Tayori.MCP.Support

    @impl true
    def execute(args, ctx) do
      author = Support.author(ctx)

      attrs =
        args
        |> Map.take([
          :title,
          :body,
          :kind,
          :category,
          :audience,
          :segments,
          :highlight,
          :version,
          :url
        ])
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.put(:ref, args[:ref] || "mcp-" <> Ecto.UUID.generate())
        |> Map.put(:author, author && (author["name"] || author[:name]))

      with :ok <- Support.categories(args[:category] && [args[:category]]),
           :ok <- Support.segments(args[:segments]),
           {:ok, change} <- Inbox.add(attrs, source: "mcp") do
        {:ok, Support.change(change)}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end
  end
end
