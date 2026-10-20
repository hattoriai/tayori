defmodule Tayori.Sources.Fragments do
  @moduledoc """
  The changes of a folder of Markdown files, one change in each: written
  in the pull request that makes the change, read when it ships. The
  pattern of [Changesets](https://github.com/changesets/changesets) and
  [towncrier](https://towncrier.readthedocs.io), whose files it reads.

      ---
      title: Exports in two clicks
      kind: added
      audience: public
      highlight: true
      ---

      Zip a whole project, with its files, notes and history, and get a
      link by email.

  The frontmatter, between `---` lines, is optional, and flat: `key:
  value`, with `true`/`false`, and `[a, b]` lists. Its keys:

    * `title` (else the first heading, or the first sentence, of the
      body), `kind` or `type`, `category`, `audience` (`public` or
      `internal`), `segments`, `highlight`, `version`, `author`, `url`,
      and `date` (`2026-10-20`, else the file's time).

  Other keys are kept in the change's `:meta`, and a Changesets file's
  package lines (`"my-package": minor`) do no harm. A towncrier name,
  `123.feature.md`, gives the kind (`feature`) when the frontmatter does
  not. The body is the Markdown after the frontmatter.

  Options:

    * `:path` - the folder (see `Tayori.Source.path/1`), required.
    * `:recursive` - the folders inside it too (`false`).
    * `:name` - the source's name (`"fragments"`).

  A file's ref is its path in the folder: change a file and the change
  stays the one it was.
  """

  @behaviour Tayori.Source

  alias Tayori.Source

  @keys ~w(title kind type category audience segments highlight version author url date)

  @impl Tayori.Source
  def name(opts), do: Keyword.get(opts, :name, "fragments")

  @impl Tayori.Source
  def changes(opts) do
    folder = opts |> Keyword.fetch!(:path) |> Source.path()
    pattern = if Keyword.get(opts, :recursive, false), do: "**/*.md", else: "*.md"

    if File.dir?(folder) do
      changes =
        folder
        |> Path.join(pattern)
        |> Path.wildcard()
        |> Enum.reject(&(Path.basename(&1) |> String.upcase() |> String.starts_with?("README")))
        |> Enum.sort()
        |> Enum.flat_map(&file(&1, folder))

      {:ok, changes}
    else
      {:error, {:folder, folder, :enoent}}
    end
  end

  defp file(path, folder) do
    with {:ok, text} <- File.read(path),
         change when is_map(change) <- parse(text, Path.relative_to(path, folder)) do
      [Map.put_new_lazy(change, :occurred_at, fn -> mtime(path) end)]
    else
      _ -> []
    end
  end

  defp mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: seconds}} -> DateTime.from_unix!(seconds, :second)
      _ -> nil
    end
  end

  @doc """
  The change of a fragment's text, named `name` in its folder, or nil for
  one with nothing to say.
  """
  @spec parse(String.t(), String.t()) :: Source.change() | nil
  def parse(text, name) do
    {front, body} = split(String.replace(text, "\r\n", "\n"))
    body = String.trim(body)
    {known, meta} = Map.split(front, @keys)

    {title, body} =
      cond do
        title = blank(known["title"]) -> {title, body}
        body != "" -> Source.title_and_body(body)
        true -> {nil, body}
      end

    if title do
      %{
        ref: name,
        title: title,
        body: if(body in [nil, ""], do: nil, else: body),
        kind: blank(known["kind"]) || blank(known["type"]) || towncrier_kind(name),
        category: blank(known["category"]),
        audience: blank(known["audience"]),
        segments: list(known["segments"]),
        highlight: known["highlight"] == true,
        version: blank(known["version"]),
        author: blank(known["author"]),
        url: blank(known["url"]),
        meta: meta
      }
      |> put_date(known["date"])
      |> Map.reject(fn {_key, value} -> value == nil end)
    end
  end

  defp split("---\n" <> rest) do
    case String.split(rest, ~r/^---\s*$/m, parts: 2) do
      [front, body] -> {frontmatter(front), body}
      [_unclosed] -> {%{}, rest}
    end
  end

  defp split(text), do: {%{}, text}

  defp frontmatter(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^\s*"?([^":]+)"?\s*:\s*(.*)$/u, line) do
        [_, key, value] -> Map.put(acc, String.trim(key), value(String.trim(value)))
        nil -> acc
      end
    end)
  end

  defp value("true"), do: true
  defp value("false"), do: false

  defp value("[" <> _ = list) do
    list
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",", trim: true)
    |> Enum.map(&unquote_value(String.trim(&1)))
  end

  defp value(text), do: unquote_value(text)

  defp unquote_value(<<q, rest::binary>>) when q in [?", ?'] do
    String.trim_trailing(rest, <<q>>)
  end

  defp unquote_value(text), do: text

  # 123.feature.md, feature.123.md: towncrier's kind of change.
  defp towncrier_kind(name) do
    parts = name |> Path.basename() |> String.split(".")

    case parts do
      [_issue, kind, "md"] when kind != "" -> if numeric?(kind), do: nil, else: kind
      _ -> nil
    end
  end

  defp numeric?(text), do: String.match?(text, ~r/^\d+$/)

  defp put_date(change, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(change, :occurred_at, DateTime.new!(date, ~T[00:00:00], "Etc/UTC"))
      _ -> change
    end
  end

  defp put_date(change, _value), do: change

  defp list(nil), do: nil
  defp list(list) when is_list(list), do: list
  defp list(text) when is_binary(text), do: String.split(text, ~r/[\s,]+/, trim: true)
  defp list(_other), do: nil

  defp blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp blank(_value), do: nil
end
