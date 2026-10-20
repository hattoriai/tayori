if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Support do
    @moduledoc false
    # What the tools share: the entries, changes and categories as the model
    # reads them, the arguments it gives checked against what the app has,
    # and the errors in words.

    import Ecto.Query

    alias Tayori.{Categories, Category, Change, Config, Entries, Entry, Resolver, Uploads}

    require Logger

    @doc "The most items a list tool returns."
    def max_limit, do: 200

    # ---- who

    @doc """
    What the principal may do, as the `:resolver` of the `:mcp` config
    says: `:all`, `:read_only` or `:forbidden`. Without a resolver,
    `:forbidden`.
    """
    @spec access(term()) :: :all | :read_only | :forbidden
    def access(principal) do
      case resolver() do
        nil ->
          Logger.warning(
            "Tayori.MCP refused a request: give the :mcp option of Tayori a :resolver " <>
              "(see the MCP guide)"
          )

          :forbidden

        resolver ->
          case resolver.resolve_access(principal) do
            access when access in [:all, :read_only] -> access
            _forbidden -> :forbidden
          end
      end
    end

    @doc "Who writes, from the principal: the resolver's `author/1`, or nil."
    @spec author(Sake.Context.t()) :: map() | nil
    def author(%{scope: principal}) do
      case resolver() do
        nil -> nil
        resolver -> Resolver.author(resolver, principal)
      end
    end

    defp resolver do
      case Config.get().mcp do
        %{resolver: resolver} -> resolver
        nil -> nil
      end
    end

    # ---- entries

    @doc "An entry by its id or its slug, with its translations."
    @spec fetch_entry(String.t()) :: {:ok, Entry.t()} | {:error, String.t()}
    def fetch_entry(id_or_slug) when is_binary(id_or_slug) do
      config = Config.get()
      id_or_slug = String.trim(id_or_slug)

      entry =
        case Ecto.UUID.cast(id_or_slug) do
          {:ok, uuid} -> Entries.get(uuid)
          :error -> config.repo.get_by(Entry, [slug: id_or_slug], prefix: config.prefix)
        end

      case entry do
        %Entry{} = entry ->
          {:ok, config.repo.preload(entry, :translations, prefix: config.prefix)}

        nil ->
          {:error, "No entry with the id or slug #{inspect(id_or_slug)}."}
      end
    end

    @doc "An entry in a line: what a list shows."
    @spec entry_summary(Entry.t(), Config.t()) :: map()
    def entry_summary(%Entry{} = entry, config) do
      translation = Entry.translation(entry, nil, config.locales)

      %{
        id: entry.id,
        slug: entry.slug,
        title: translation && translation.title,
        status: Entry.status(entry),
        published_at: timestamp(entry.published_at),
        pinned: entry.pinned_at != nil,
        categories: entry.categories,
        segments: entry.segments,
        locales: Enum.map(entry.translations, & &1.locale),
        url: url(entry, config)
      }
    end

    @doc "An entry whole: its translations, their bodies in Markdown."
    @spec entry_detail(Entry.t(), Config.t()) :: map()
    def entry_detail(%Entry{} = entry, config) do
      present = Enum.map(entry.translations, & &1.locale)

      entry
      |> entry_summary(config)
      |> Map.drop([:title, :locales])
      |> Map.merge(%{
        author: entry.author,
        updated_at: timestamp(entry.updated_at),
        translations:
          Enum.map(entry.translations, fn t ->
            %{locale: t.locale, title: t.title, summary: t.summary, body: markdown(t.body)}
          end),
        missing_locales: Enum.reject(config.locales, &(&1 in present))
      })
    end

    # The entry on the public page: one for everyone, when the app gives
    # the page's address.
    defp url(%Entry{segments: [], slug: slug}, %Config{page_url: page})
         when is_binary(page),
         do: page <> "/" <> slug

    defp url(_entry, _config), do: nil

    @doc "A body as Markdown."
    @spec markdown(Kotoba.Content.t() | nil) :: String.t()
    def markdown(%Kotoba.Content{doc: doc}) do
      case Kotoba.Document.parse(doc) do
        {:ok, document} -> Kotoba.Renderer.to_markdown(document)
        _error -> ""
      end
    end

    def markdown(_nil), do: ""

    @doc """
    The Markdown of a body as an entry keeps it: an image uploaded with
    `request_upload` or `upload_image` becomes its attachment.
    """
    @spec body(String.t()) :: Kotoba.Content.t()
    def body(markdown), do: Uploads.content(markdown)

    # ---- changes

    @doc "A change of the inbox."
    @spec change(Change.t()) :: map()
    def change(%Change{} = change) do
      %{
        id: change.id,
        source: change.source,
        ref: change.ref,
        title: change.title,
        body: change.body,
        kind: change.kind,
        category: change.category,
        audience: change.audience,
        segments: change.segments,
        highlight: change.highlight,
        version: change.version,
        url: change.url,
        author: change.author,
        occurred_at: timestamp(change.occurred_at),
        state: change.state,
        entry_id: change.entry_id
      }
    end

    @doc "A change by its id."
    @spec fetch_change(String.t()) :: {:ok, Change.t()} | {:error, String.t()}
    def fetch_change(id) do
      case Tayori.Inbox.get(id) do
        %Change{} = change -> {:ok, change}
        nil -> {:error, "No change with the id #{inspect(id)}."}
      end
    end

    @doc "Whether the inbox has the change of a source and a ref."
    @spec change_exists?(String.t(), String.t()) :: boolean()
    def change_exists?(source, ref) do
      config = Config.get()

      from(c in Change, where: c.source == ^source and c.ref == ^ref)
      |> config.repo.exists?(prefix: config.prefix)
    end

    @doc "Ids of changes, checked."
    @spec change_ids([String.t()]) :: {:ok, [Ecto.UUID.t()]} | {:error, String.t()}
    def change_ids(ids) do
      case Enum.reject(ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        [] -> {:ok, Enum.map(ids, &String.downcase/1)}
        bad -> {:error, "Not ids of changes: #{Enum.join(bad, ", ")}."}
      end
    end

    @doc "The ids of the changes an entry was made of."
    @spec drafted_ids(Entry.t()) :: [Ecto.UUID.t()]
    def drafted_ids(%Entry{id: id}) do
      config = Config.get()

      from(c in Change, where: c.entry_id == ^id, order_by: c.occurred_at, select: c.id)
      |> config.repo.all(prefix: config.prefix)
    end

    # ---- categories and segments

    @doc "A category, named in each language."
    @spec category(Category.t(), Config.t()) :: map()
    def category(%Category{} = category, config) do
      %{
        key: category.key,
        name: Category.name(category, nil, config.locales),
        names: category.names,
        color: category.color
      }
    end

    @doc "Checks that categories are the keys of the app's."
    @spec categories(nil | [String.t()]) :: :ok | {:error, String.t()}
    def categories(nil), do: :ok

    def categories(keys) do
      known = Enum.map(Categories.list(), & &1.key)

      case Enum.reject(keys, &(&1 in known)) do
        [] ->
          :ok

        unknown ->
          {:error,
           "Unknown categories: #{Enum.join(unknown, ", ")}. The categories are " <>
             "#{list(known)}: give their keys (list_categories)."}
      end
    end

    @doc """
    Checks that segments are the resolver's, when it says which there
    are (`c:Tayori.Resolver.segments/0`).
    """
    @spec segments(nil | [String.t()]) :: :ok | {:error, String.t()}
    def segments(nil), do: :ok
    def segments([]), do: :ok

    def segments(segments) do
      known =
        case resolver() do
          nil ->
            []

          resolver ->
            for {_group, list} <- Resolver.segment_groups(resolver), {s, _} <- list, do: s
        end

      case Enum.reject(segments, &(&1 in known)) do
        [] ->
          :ok

        unknown ->
          {:error,
           "Unknown segments: #{Enum.join(unknown, ", ")}. The segments are #{list(known)}; " <>
             "an entry with none is for everyone."}
      end
    end

    defp list([]), do: "none"
    defp list(items), do: Enum.join(items, ", ")

    @doc "A locale of the app, the first by default."
    @spec locale(String.t() | nil, Config.t()) :: {:ok, String.t()} | {:error, String.t()}
    def locale(nil, config), do: {:ok, Config.default_locale(config)}

    def locale(locale, config) do
      if locale in config.locales,
        do: {:ok, locale},
        else:
          {:error,
           "Unknown language #{inspect(locale)}: the entries are written in " <>
             "#{Enum.join(config.locales, ", ")}."}
    end

    @doc "A time in ISO 8601."
    @spec time(String.t()) :: {:ok, DateTime.t()} | {:error, String.t()}
    def time(text) do
      case DateTime.from_iso8601(text) do
        {:ok, at, _offset} ->
          {:ok, at}

        {:error, _} ->
          {:error,
           "#{inspect(text)} is not a time: give one in ISO 8601, as 2026-11-02T09:00:00Z."}
      end
    end

    # ---- errors and values

    @doc "An error as the model reads it."
    @spec error(term()) :: String.t()
    def error(%Ecto.Changeset{} = changeset) do
      changeset
      |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
        Regex.replace(~r"%{(\w+)}", message, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)
      |> flatten([])
      |> Enum.uniq()
      |> Enum.join("; ")
      |> Kernel.<>(".")
    end

    def error(message) when is_binary(message), do: message

    def error(other) do
      Logger.warning("Tayori.MCP: #{inspect(other)}")
      "It failed."
    end

    # "translations: title can't be blank", for a nested changeset's.
    defp flatten(errors, path) when is_map(errors) do
      Enum.flat_map(errors, fn {field, value} -> flatten(value, path ++ [field]) end)
    end

    defp flatten(errors, path) when is_list(errors) do
      Enum.flat_map(errors, fn
        message when is_binary(message) -> ["#{Enum.join(path, " ")} #{message}"]
        nested -> flatten(nested, path)
      end)
    end

    @doc "A time as ISO 8601, or nil."
    @spec timestamp(DateTime.t() | nil) :: String.t() | nil
    def timestamp(nil), do: nil
    def timestamp(%DateTime{} = at), do: DateTime.to_iso8601(at)
  end
end
