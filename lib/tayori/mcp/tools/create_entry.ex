if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.CreateEntry do
    @moduledoc false
    use Sake.Tool,
      name: "create_entry",
      title: "Write an entry",
      description:
        "Write a new entry, as a draft, in the app's first language (the others with " <>
          "update_entry). The body is Markdown: headings, lists, links, code, tables; an " <>
          "image uploaded with request_upload or upload_image, alone in its paragraph, " <>
          "becomes a figure with its alternative text as the caption. It is published " <>
          "only by publish_entry.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: false]

    arg :title, :string, required: true, max_length: 255, description: "The title"

    arg :summary, :string,
      max_length: 500,
      description: "A sentence or two, what the panel and the emails show"

    arg :body, :string, max_length: 200_000, description: "The body, in Markdown"

    arg :locale, :string,
      max_length: 35,
      description: "Its language, the app's first by default (the first is required)"

    arg :categories, {:array, :string},
      description: "The keys of its categories (list_categories)"

    arg :segments, {:array, :string},
      description: "The readers it is for, when not everyone (the app's segments)"

    alias Tayori.{Config, Entries}
    alias Tayori.MCP.Support

    @impl true
    def execute(args, ctx) do
      config = Config.get()

      with {:ok, locale} <- Support.locale(args[:locale], config),
           :ok <- Support.categories(args[:categories]),
           :ok <- Support.segments(args[:segments]),
           {:ok, entry} <- Entries.create(attrs(args, locale), author: Support.author(ctx)) do
        {:ok, Support.entry_detail(Entries.get!(entry.id), config)}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end

    defp attrs(args, locale) do
      %{
        "categories" => args[:categories] || [],
        "segments" => args[:segments] || [],
        "translations" => [
          %{
            "locale" => locale,
            "title" => args.title,
            "summary" => args[:summary],
            "body" => Support.body(args[:body] || "")
          }
        ]
      }
    end
  end
end
