defmodule Tayori.GitHub do
  @moduledoc """
  Changes from GitHub: a webhook of the repository, at
  `POST /hooks/github` of the JSON API (`Tayori.API`). The
  [Automation](automation.md) guide adds it in GitHub.

  GitHub signs each delivery with the webhook's secret
  (`x-hub-signature-256`), and Tayori checks it against the body as it
  came. The admin makes the secret, `new_secret/0`, and pastes it into
  GitHub; Tayori keeps it encrypted, as the AI key (the `:vault` or the
  `:secret_key_base` of `Tayori.Config`).

  Two events make changes:

    * A pull request merged into the default branch: one change, its
      `:ref` the repository and the number (`"owner/repo#123"`). Its
      title is the pull request's, and its body the section of the pull
      request's description headed `## Changelog` or `## Release notes`,
      when there is one: never the whole description, which is often for
      the team. A pull request closed without a merge is nothing.
    * A release published: each item of its notes, as
      `Tayori.Sources.Changelog` reads them. Items under `### Added` have
      that kind; items with no section have none. Notes with no item are
      one change, titled with the release's name. A prerelease is nothing
      yet.

  A pull request's labels say what the change is, with the prefix of the
  `:github` option of the `:inbox` config (`"changelog:"`):

    * `changelog:skip` - no change.
    * `changelog:internal` - for the team only; `changelog:public` - for
      everyone.
    * `changelog:highlight` - worth leading with.
    * `changelog:category:<key>` - its category.
    * `changelog:segment:<segment>` - the readers it is for (one label
      each).
    * `changelog:<kind>` - its kind (`changelog:added`,
      `changelog:fixed`), and so its category (the `:kinds` of the
      `:inbox` config).

  With `only_labeled: true`, a pull request with none of these labels is
  nothing.

  ## The raw body

  The signature is of the body as GitHub sent it. An endpoint whose
  `Plug.Parsers` reads JSON (a Phoenix app's does) reads the body before
  the router; PhoenixMountable's reader asks the router which plug a
  request goes to and keeps a copy of the body for the plugs that ask for
  it (Tayori's hooks do), wherever their routes are mounted:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        body_reader: {PhoenixMountable.RawBody, :read_body, [MyAppWeb.Router]},
        json_decoder: Phoenix.json_library()

  `mix tayori.install` writes it. Without it, a delivery is answered with
  a 500, and the log says why.
  """

  alias Tayori.{Config, Settings, Source}
  alias Tayori.Sources.Changelog

  @setting "github"

  @doc """
  Makes the webhook's secret, in place of any other, and returns it, to
  paste into GitHub. Tayori keeps it encrypted, and never shows it again.
  `{:error, :no_secrets}` without a `:vault` or a `:secret_key_base`.
  """
  @spec new_secret() :: {:ok, String.t()} | {:error, :no_secrets}
  def new_secret do
    if Settings.secrets?() do
      secret = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      Settings.put(@setting, %{"created_at" => DateTime.to_iso8601(DateTime.utc_now())}, secret)
      {:ok, secret}
    else
      {:error, :no_secrets}
    end
  end

  @doc "Whether there is a webhook secret."
  @spec secret?() :: boolean()
  def secret?, do: Settings.secret?(@setting)

  @doc "Removes the webhook's secret: GitHub's deliveries get a 404."
  @spec remove_secret() :: :ok
  def remove_secret, do: Settings.put(@setting, %{}, nil)

  @doc """
  Checks the signature of a body, the `x-hub-signature-256` header
  (`sha256=<hex>`), in constant time. Returns `:ok`, `{:error,
  :no_secret}`, or `{:error, :invalid}`.
  """
  @spec verify(binary(), String.t() | nil) :: :ok | {:error, :no_secret | :invalid}
  def verify(body, signature) when is_binary(body) do
    case Settings.secret(@setting) do
      nil ->
        {:error, :no_secret}

      secret ->
        expected =
          "sha256=" <>
            (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

        if is_binary(signature) and
             Plug.Crypto.secure_compare(expected, String.downcase(String.trim(signature))),
           do: :ok,
           else: {:error, :invalid}
    end
  end

  @doc """
  A body reader for `Plug.Parsers` (`body_reader: {Tayori.GitHub,
  :read_body, []}`): it reads the body as `Plug.Conn.read_body/2` does,
  and keeps a copy of a body GitHub signed, for `verify/2`. The same as
  `Tayori.RawBody.read_body/2`, which also keeps the bodies of the mail
  providers' webhooks.

  Deprecated: `{PhoenixMountable.RawBody, :read_body, [MyAppWeb.Router]}`
  takes its place, and keeps the bodies of every library that asks for
  them. This one still works.
  """
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts), do: Tayori.RawBody.read_body(conn, opts)

  @doc """
  The changes of an event of GitHub, `x-github-event` and its payload:
  `{:ok, changes}` (none for a `ping`, or a pull request that is not
  news), or `:ignore` for an event Tayori does not read. The options are
  those of the `:github` option of the `:inbox` config, which they
  replace.
  """
  @spec handle(String.t(), map(), keyword()) :: {:ok, [Source.change()]} | :ignore
  def handle(event, payload, opts \\ [])

  def handle("ping", _payload, _opts), do: {:ok, []}

  def handle("pull_request", %{"action" => "closed", "pull_request" => pr} = payload, opts)
      when is_map(pr) do
    if pr["merged"] == true or pr["merged_at"] != nil,
      do: {:ok, pull_request(pr, payload["repository"] || %{}, options(opts))},
      else: :ignore
  end

  def handle("release", %{"action" => "published", "release" => release} = payload, _opts)
      when is_map(release) do
    if release["draft"] == true or release["prerelease"] == true,
      do: :ignore,
      else: {:ok, release(release, payload["repository"] || %{})}
  end

  def handle(_event, _payload, _opts), do: :ignore

  defp options(opts) do
    defaults = Config.get().inbox.github

    %{
      label_prefix:
        opts |> Keyword.get(:label_prefix, defaults.label_prefix) |> String.downcase(),
      only_labeled: Keyword.get(opts, :only_labeled, defaults.only_labeled)
    }
  end

  # ── Pull requests ───────────────────────────────────────────────

  defp pull_request(pr, repo, opts) do
    labels = for %{"name" => name} <- pr["labels"] || [], is_binary(name), do: name
    ours = ours(labels, opts.label_prefix)

    cond do
      "skip" in ours -> []
      opts.only_labeled and ours == [] -> []
      other_branch?(pr, repo) -> []
      true -> [pull_request_change(pr, repo, labels, ours)]
    end
  end

  # Merged into a branch that is not the default: not shipped yet.
  defp other_branch?(pr, repo) do
    case {get_in(pr, ["base", "ref"]), repo["default_branch"]} do
      {base, default} when is_binary(base) and is_binary(default) -> base != default
      _unknown -> false
    end
  end

  defp ours(labels, prefix) do
    for label <- labels,
        lower = String.downcase(String.trim(label)),
        String.starts_with?(lower, prefix),
        rest = lower |> String.replace_prefix(prefix, "") |> String.trim(),
        rest != "",
        do: rest
  end

  defp pull_request_change(pr, repo, labels, ours) do
    name = repo["full_name"]
    number = pr["number"]

    %{
      ref: if(name, do: "#{name}##{number}", else: "pr-#{number}"),
      title: pr["title"],
      body: changelog_section(pr["body"]),
      kind: Enum.find(ours, &kind?/1),
      category: Enum.find_value(ours, &tagged(&1, "category:")),
      audience: audience(ours),
      segments: ours |> Enum.map(&tagged(&1, "segment:")) |> Enum.reject(&is_nil/1),
      highlight: "highlight" in ours,
      url: pr["html_url"],
      author: get_in(pr, ["user", "login"]),
      occurred_at: pr["merged_at"],
      meta: %{"repository" => name, "number" => number, "labels" => labels}
    }
    |> Map.reject(fn {_key, value} -> value in [nil, []] end)
  end

  defp kind?(label) do
    label not in ~w(skip internal public highlight) and
      not String.starts_with?(label, ["category:", "segment:"])
  end

  defp tagged(label, tag) do
    case String.split(label, tag, parts: 2) do
      ["", value] when value != "" -> String.trim(value)
      _ -> nil
    end
  end

  defp audience(ours) do
    cond do
      "internal" in ours -> "internal"
      "public" in ours -> "public"
      true -> nil
    end
  end

  @doc """
  The section of a pull request's description for its readers: the text
  under a heading `Changelog`, `Change log` or `Release notes`, to the
  next heading of its level, without HTML comments. Nil when there is no
  such section, or it is empty.

      iex> Tayori.GitHub.changelog_section("Fixes #12.\\n\\n## Changelog\\n\\nExports are faster.\\n\\n## Tests\\n\\nAdded.")
      "Exports are faster."
  """
  @spec changelog_section(String.t() | nil) :: String.t() | nil
  def changelog_section(text) when is_binary(text) do
    lines = text |> without_comments() |> String.split("\n")

    lines
    |> Enum.drop_while(&(section_level(&1) == nil))
    |> case do
      [] ->
        nil

      [heading | rest] ->
        level = section_level(heading)

        rest
        |> Enum.take_while(&(heading_level(&1) > level))
        |> Enum.join("\n")
        |> String.trim()
        |> blank()
    end
  end

  def changelog_section(_text), do: nil

  defp section_level(line) do
    case Regex.run(~r/^\s{0,3}(\#{1,6})\s+(change\s?log|release\s+notes?)\s*:?\s*#*\s*$/iu, line) do
      [_, hashes, _] -> String.length(hashes)
      nil -> nil
    end
  end

  # The level of a heading; a line of text is under every heading.
  defp heading_level(line) do
    case Regex.run(~r/^\s{0,3}(\#{1,6})\s/u, line) do
      [_, hashes] -> String.length(hashes)
      nil -> 7
    end
  end

  defp without_comments(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace(~r/<!--.*?-->/su, "")
  end

  # ── Releases ────────────────────────────────────────────────────

  defp release(release, repo) do
    tag = release["tag_name"] || ""
    name = repo["full_name"]
    prefix = if name, do: "#{name}@", else: ""
    notes = release_notes(release["body"] || "")

    common = %{
      version: tag,
      url: release["html_url"],
      author: get_in(release, ["author", "login"]),
      occurred_at: release["published_at"],
      meta: %{"repository" => name, "release" => release["name"]}
    }

    case Changelog.parse("## [#{tag}]\n\n" <> notes, :all) do
      [] ->
        whole(release, tag, notes, prefix, common)

      changes ->
        Enum.map(changes, &item(&1, prefix, common))
    end
  end

  defp item(change, prefix, common) do
    change
    |> Map.merge(common)
    |> Map.put(:ref, prefix <> change.ref)
    |> Map.reject(fn {_key, value} -> value == nil end)
  end

  # Notes with no item: one change, when they say anything.
  defp whole(release, tag, notes, prefix, common) do
    case String.trim(notes) do
      "" ->
        []

      body ->
        title = blank(release["name"]) || tag

        [
          common
          |> Map.merge(%{ref: prefix <> tag, title: title, body: body})
          |> Map.reject(fn {_key, value} -> value == nil end)
        ]
    end
  end

  # The notes as a changelog's release: without their top headings and
  # the list of new contributors, and without GitHub's "by @someone in
  # <link>" after each item of notes it wrote.
  defp release_notes(body) do
    body
    |> without_comments()
    |> String.split("\n")
    |> Enum.reduce({[], false}, fn line, {lines, skipping} ->
      case Regex.run(~r/^\s{0,3}\#{1,2}\s+(.*?)\s*#*\s*$/u, line) do
        [_, heading] ->
          {lines, String.downcase(heading) == "new contributors"}

        nil when skipping ->
          {lines, skipping}

        nil ->
          {[String.replace(line, ~r/\s+by @[\w.-]+ in https?:\/\/\S+\s*$/u, "") | lines], false}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp blank(_value), do: nil
end
