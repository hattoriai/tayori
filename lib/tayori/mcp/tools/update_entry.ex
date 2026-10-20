if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.UpdateEntry do
    @moduledoc false
    use Sake.Tool,
      name: "update_entry",
      title: "Change an entry",
      description:
        "Change an entry: its title, summary and body in one language (the app's first by " <>
          "default; a language it does not have yet is added, with a title), and its " <>
          "categories and segments. Only what is given changes; the body is replaced " <>
          "whole, in Markdown, as create_entry takes it. Its status never changes: " <>
          "a published entry changes for its readers at once.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: true, idempotent: true, open_world: false]

    arg :id, :string, required: true, max_length: 160, description: "The entry's id, or its slug"

    arg :locale, :string,
      max_length: 35,
      description: "The language of the text (the app's first)"

    arg :title, :string, max_length: 255, description: "The title"
    arg :summary, :string, max_length: 500, description: "The summary; empty takes it off"
    arg :body, :string, max_length: 200_000, description: "The body, in Markdown"

    arg :categories, {:array, :string},
      description: "The keys of its categories (list_categories)"

    arg :segments, {:array, :string},
      description: "The readers it is for; empty for everyone (the app's segments)"

    alias Tayori.{Config, Entries}
    alias Tayori.MCP.Support

    @text [:title, :summary, :body]

    @impl true
    def execute(args, _ctx) do
      config = Config.get()

      with {:ok, entry} <- Support.fetch_entry(args.id),
           {:ok, locale} <- Support.locale(args[:locale], config),
           :ok <- Support.categories(args[:categories]),
           :ok <- Support.segments(args[:segments]),
           {:ok, attrs} <- attrs(entry, args, locale),
           {:ok, entry} <- Entries.update(entry, attrs) do
        {:ok, Support.entry_detail(Entries.get!(entry.id), config)}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end

    defp attrs(entry, args, locale) do
      text = text(args)
      fields = args |> Map.take([:categories, :segments]) |> stringify()

      cond do
        String.trim(text["title"] || "-") == "" ->
          {:error, "A title cannot be empty."}

        text == %{} and fields == %{} ->
          {:error, "Nothing to change: give a title, a summary, a body, categories or segments."}

        text == %{} ->
          {:ok, fields}

        true ->
          {:ok, Map.put(fields, "translations", translations(entry, locale, text))}
      end
    end

    defp text(args) do
      args
      |> Map.take(@text)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn
        {:body, markdown} -> {"body", Support.body(markdown)}
        {key, value} -> {Atom.to_string(key), value}
      end)
    end

    defp stringify(map) do
      map
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    end

    # Every translation by its id, so that the others stay; the language's
    # with the text, or a new one.
    defp translations(entry, locale, text) do
      existing =
        Enum.map(entry.translations, fn t ->
          if t.locale == locale, do: Map.put(text, "id", t.id), else: %{"id" => t.id}
        end)

      if Enum.any?(entry.translations, &(&1.locale == locale)),
        do: existing,
        else: existing ++ [Map.put(text, "locale", locale)]
    end
  end
end
