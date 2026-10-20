defmodule Tayori.Source do
  @moduledoc """
  Where the changes of the inbox come from: a file of the app, a folder of
  files, a service. A source is a module with `c:changes/1`, named in the
  `:sources` of the `:inbox` config with its options:

      inbox: [
        sources: [
          {Tayori.Sources.Changelog, path: {:my_app, "priv/CHANGELOG.md"}},
          {Tayori.Sources.Fragments, path: {:my_app, "priv/news"}},
          {MyApp.ReleaseNotes, url: "https://..."}
        ]
      ]

  Tayori reads them when the app starts (`:ingest_on_start`) and when
  `Tayori.Inbox.ingest/0` is called. A change a source gives again, with
  the same `:ref`, is not added twice, so a source gives all it has each
  time.

  Tayori has two: `Tayori.Sources.Changelog` (a Keep a Changelog file)
  and `Tayori.Sources.Fragments` (a folder of Markdown files, as
  Changesets and towncrier write them).
  """

  @typedoc """
  A change as a source gives it: the attributes of `Tayori.Change`, with
  string or atom keys. `:ref` and `:title` are needed.
  """
  @type change :: map()

  @doc "The changes the source has now, all of them."
  @callback changes(opts :: keyword()) :: {:ok, [change()]} | {:error, term()}

  @doc "The name of the source, for `Tayori.Change`'s `:source` (the module's last part, lowercased)."
  @callback name(opts :: keyword()) :: String.t()

  @optional_callbacks name: 1

  @doc false
  # The name a source's changes take.
  @spec name(module(), keyword()) :: String.t()
  def name(module, opts) do
    if function_exported?(module, :name, 1) do
      module.name(opts)
    else
      module |> Module.split() |> List.last() |> Macro.underscore()
    end
  end

  @doc """
  The path of a source's file or folder: an absolute path; a path
  relative to the current directory; or `{otp_app, path}`, relative to
  the app's directory (`Application.app_dir/2`), which is where a release
  keeps `priv/`.
  """
  @spec path(Path.t() | {atom(), Path.t()}) :: Path.t()
  def path({app, relative}) when is_atom(app) and is_binary(relative),
    do: Application.app_dir(app, relative)

  def path(path) when is_binary(path), do: Path.expand(path)

  @doc false
  # A short, stable name of a text, for a ref.
  @spec hash(String.t()) :: String.t()
  def hash(text) do
    :sha256 |> :crypto.hash(text) |> Base.url_encode64(padding: false) |> binary_part(0, 16)
  end

  @doc false
  # The title of a change from its Markdown, and what is left of it for
  # the body: its first heading, or the first sentence of its first
  # paragraph, without the marks. A body that was only its title is nil.
  @spec title_and_body(String.t()) :: {String.t(), String.t() | nil}
  def title_and_body(markdown) do
    [first | rest] =
      case markdown |> String.trim() |> String.split(~r/\n\s*\n/, parts: 2) do
        [""] -> [""]
        blocks -> blocks
      end

    {title, left} =
      case Regex.run(~r/\A#+\s*(.*?)\s*(?:\n(.*))?\z/s, first) do
        [_, heading | left] -> {heading, Enum.join(left)}
        nil -> sentence(first |> String.split("\n") |> Enum.map_join(" ", &String.trim/1))
      end

    body =
      [left | rest] |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")

    {clean(title), if(body == "", do: nil, else: body)}
  end

  defp sentence(paragraph) do
    case Regex.run(~r/\A(.+?[.!?])(?:\s+(.*))?\z/su, paragraph) do
      [_, sentence | left] -> {sentence, Enum.join(left)}
      nil -> {paragraph, ""}
    end
  end

  defp clean(title) do
    title
    |> String.replace(~r/\[([^\]]*)\]\([^)]*\)/u, "\\1")
    |> String.replace(~r/[*_`~]/u, "")
    |> String.trim()
    |> String.trim_trailing(".")
    |> truncate(255)
  end

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end
end
