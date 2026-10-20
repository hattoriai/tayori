defmodule Tayori.Sources.Changelog do
  @moduledoc """
  The changes of a `CHANGELOG.md` in the [Keep a
  Changelog](https://keepachangelog.com) format: each item of each
  release is a change.

      ## [1.4.0] - 2026-10-20

      ### Added

      - Exports in two clicks: zip a project with its files.

      ### Fixed

      - Dates showed a day early in Auckland.

  The change's `:version` is the release's (`1.4.0`), its `:kind` the
  section's (`added`, `fixed`, ...), its `:occurred_at` the release's
  date, its `:body` the item, and its `:title` the item's first sentence.
  An item can say more about itself in a comment that ends it,
  `<!-- audience: internal -->` or `<!-- category: api, highlight -->`.

  Options:

    * `:path` - the file (see `Tayori.Source.path/1`), required.
    * `:sections` - `:released` (the releases with a version, not
      `[Unreleased]`) or `:all` (`:released`).
    * `:name` - the source's name (`"changelog"`).
  """

  @behaviour Tayori.Source

  alias Tayori.Source

  @impl Tayori.Source
  def name(opts), do: Keyword.get(opts, :name, "changelog")

  @impl Tayori.Source
  def changes(opts) do
    path = opts |> Keyword.fetch!(:path) |> Source.path()

    case File.read(path) do
      {:ok, text} -> {:ok, parse(text, Keyword.get(opts, :sections, :released))}
      {:error, reason} -> {:error, {:file, path, reason}}
    end
  end

  @doc """
  The changes of a changelog's text: `:released` sections only, or
  `:all`.
  """
  @spec parse(String.t(), :released | :all) :: [Source.change()]
  def parse(text, sections \\ :released) do
    text
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.reduce(%{release: nil, kind: nil, items: [], current: nil}, &line/2)
    |> close_item()
    |> Map.fetch!(:items)
    |> Enum.reverse()
    |> Enum.filter(&(sections == :all or &1.version != nil))
    |> Enum.map(&change/1)
  end

  # A release: `## [1.4.0] - 2026-10-20`, `## 1.4.0`, `## [Unreleased]`.
  defp line("## " <> heading, acc) do
    acc = close_item(acc)
    %{acc | release: release(heading), kind: nil}
  end

  # A kind of change: `### Added`.
  defp line("### " <> heading, acc) do
    acc = close_item(acc)
    %{acc | kind: heading |> String.trim() |> String.downcase()}
  end

  # An item: `- ...` or `* ...` at the start of the line.
  defp line(<<bullet, " ", rest::binary>>, %{release: release} = acc)
       when bullet in [?-, ?*] and release != nil do
    acc = close_item(acc)
    %{acc | current: [rest]}
  end

  # The rest of an item: an indented or blank line while one is open.
  defp line(text, %{current: lines} = acc) when is_list(lines) do
    cond do
      String.trim(text) == "" -> %{acc | current: [text | lines]}
      String.match?(text, ~r/^\s+/) -> %{acc | current: [text | lines]}
      true -> close_item(acc)
    end
  end

  defp line(_text, acc), do: acc

  defp close_item(%{current: nil} = acc), do: acc

  defp close_item(%{current: lines} = acc) do
    body = lines |> Enum.reverse() |> Enum.map_join("\n", &dedent/1) |> String.trim()

    item = %{
      version: acc.release && acc.release.version,
      date: acc.release && acc.release.date,
      kind: acc.kind,
      body: body
    }

    %{acc | items: [item | acc.items], current: nil}
  end

  defp dedent(line), do: String.replace(line, ~r/^ {1,4}/, "")

  defp release(heading) do
    heading = String.trim(heading)

    case Regex.run(~r/^\[?([^\]\s]+)\]?(?:\s*[-–—]\s*(\d{4}-\d{2}-\d{2}))?/u, heading) do
      [_, name | date] ->
        version = if String.downcase(name) == "unreleased", do: nil, else: name
        %{version: version, date: date |> List.first() |> date()}

      nil ->
        %{version: nil, date: nil}
    end
  end

  defp date(nil), do: nil

  defp date(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> nil
    end
  end

  # An item's own words about itself, in a comment at its end.
  defp change(%{body: body} = item) do
    {body, notes} = notes(body)

    %{
      ref: "#{item.version || "unreleased"}/#{Source.hash(body)}",
      title: Source.title(body),
      body: body,
      kind: item.kind,
      version: item.version,
      occurred_at: item.date
    }
    |> Map.merge(notes)
  end

  defp notes(body) do
    case Regex.run(~r/\s*<!--(.*?)-->\s*\z/s, body) do
      [comment, inner] ->
        {String.replace_suffix(body, comment, "") |> String.trim(), parse_notes(inner)}

      nil ->
        {body, %{}}
    end
  end

  defp parse_notes(inner) do
    inner
    |> String.split(~r/[,;]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn note, notes ->
      case String.split(note, ":", parts: 2) do
        ["highlight"] -> Map.put(notes, :highlight, true)
        [key, value] -> note(notes, String.trim(key), String.trim(value))
        _ -> notes
      end
    end)
  end

  defp note(notes, "audience", value), do: Map.put(notes, :audience, value)
  defp note(notes, "category", value), do: Map.put(notes, :category, value)
  defp note(notes, "highlight", value), do: Map.put(notes, :highlight, value in ["true", "yes"])

  defp note(notes, "segments", value),
    do: Map.put(notes, :segments, String.split(value, ~r/\s+/, trim: true))

  defp note(notes, _key, _value), do: notes
end
