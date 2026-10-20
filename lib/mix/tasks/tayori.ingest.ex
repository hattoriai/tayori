defmodule Mix.Tasks.Tayori.Ingest do
  @shortdoc "Adds the changes of the sources to Tayori's inbox, here or in a running app"

  @moduledoc """
  Adds changes to Tayori's inbox (`Tayori.Inbox`), in two ways.

  In the app, with its database: it starts the app and reads every source
  of the `:inbox` config, as `Tayori.Inbox.ingest/0` does.

      $ mix tayori.ingest

  From CI, to an app that runs elsewhere: it reads a changelog and a
  folder of fragments here, and sends their changes to the app's
  `POST /changes` (`Tayori.Ingest`). It does not start the app, and needs
  no database.

      $ mix tayori.ingest --url https://myapp.com/api/machines/news \\
          --token "$TAYORI_INGEST_TOKEN" \\
          --changelog CHANGELOG.md --fragments priv/news

  Options of the second way:

    * `--url` - the address of the JSON API mounted for machines.
    * `--token` - the ingest token (else the `TAYORI_INGEST_TOKEN`
      environment variable).
    * `--changelog` - a Keep a Changelog file (`Tayori.Sources.Changelog`).
    * `--fragments` - a folder of fragments (`Tayori.Sources.Fragments`);
      `--recursive` reads the folders inside it too.
    * `--source` - the source of every change sent (`"changelog"` and
      `"fragments"`, as the sources of the config name theirs).

  It sends 500 changes a request at most, and needs the `:req`
  dependency. It prints how many were new, and fails when a request
  fails or a change is invalid.

  In a release, with no Mix, the first way is to ask the running app:
  `bin/my_app rpc "IO.inspect(Tayori.Inbox.ingest())"`. Not `eval`, whose
  node does not start the app.
  """

  use Mix.Task

  alias Tayori.Sources.{Changelog, Fragments}

  # Req is an optional dependency, needed to send.
  @compile {:no_warn_undefined, Req}

  @switches [
    url: :string,
    token: :string,
    changelog: :string,
    fragments: :string,
    recursive: :boolean,
    source: :string
  ]

  @batch 500
  # Under the endpoint's megabyte, with room to spare.
  @batch_bytes 900_000

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    if rest != [] or invalid != [] do
      Mix.raise("Unknown arguments: #{Enum.join(rest ++ Enum.map(invalid, &elem(&1, 0)), " ")}")
    end

    if opts[:url], do: send_changes(opts), else: ingest(opts)
  end

  # ── In the app ──────────────────────────────────────────────────

  defp ingest(opts) do
    if opts != [] do
      Mix.raise("--#{opts |> hd() |> elem(0)} needs --url: without it, the app reads its sources")
    end

    Mix.Task.run("app.start")
    results = Tayori.Inbox.ingest()

    if results == %{} do
      Mix.shell().info("The :inbox config has no sources")
    end

    failed =
      for {name, result} <- Enum.sort(results), reduce: [] do
        failed ->
          case result do
            {:ok, counts} ->
              Mix.shell().info(line(name, counts))
              failed

            {:error, reason} ->
              Mix.shell().error("#{name}: #{inspect(reason)}")
              [name | failed]
          end
      end

    if failed != [] do
      Mix.raise("Tayori could not read #{failed |> Enum.reverse() |> Enum.join(", ")}")
    end
  end

  # ── From CI ─────────────────────────────────────────────────────

  defp send_changes(opts) do
    token = opts[:token] || System.get_env("TAYORI_INGEST_TOKEN")

    cond do
      token in [nil, ""] ->
        Mix.raise("--url needs the ingest token: --token, or TAYORI_INGEST_TOKEN")

      opts[:changelog] == nil and opts[:fragments] == nil ->
        Mix.raise("Give --changelog, --fragments or both: the changes to send")

      not Code.ensure_loaded?(Req) ->
        Mix.raise("Sending the changes needs the :req dependency: add {:req, \"~> 0.5\"}")

      true ->
        {:ok, _} = Application.ensure_all_started(:req)
        changes = read(opts)
        url = String.trim_trailing(opts[:url], "/") <> "/changes"

        totals =
          changes
          |> batches()
          |> Enum.reduce(%{added: 0, existing: 0, errors: []}, fn {batch, offset}, totals ->
            post!(url, token, batch, offset, totals)
          end)

        report(changes, totals)
    end
  end

  defp read(opts) do
    source = opts[:source]

    changelog =
      with path when is_binary(path) <- opts[:changelog] do
        case Changelog.changes(path: path) do
          {:ok, changes} -> with_source(changes, source || "changelog")
          {:error, _reason} -> Mix.raise("Cannot read the changelog #{path}")
        end
      end

    fragments =
      with path when is_binary(path) <- opts[:fragments] do
        case Fragments.changes(path: path, recursive: opts[:recursive] == true) do
          {:ok, changes} -> with_source(changes, source || "fragments")
          {:error, _reason} -> Mix.raise("Cannot read the folder #{path}")
        end
      end

    (changelog || []) ++ (fragments || [])
  end

  defp with_source(changes, source), do: Enum.map(changes, &Map.put(&1, :source, source))

  # The changes in requests of 500 at most, each under a megabyte, with
  # the index of their first.
  defp batches(changes) do
    changes
    |> Enum.with_index()
    |> Enum.chunk_while(
      {[], 0},
      fn {change, index}, {batch, bytes} ->
        size = byte_size(JSON.encode!(change))

        if batch != [] and (length(batch) >= @batch or bytes + size > @batch_bytes) do
          {:cont, Enum.reverse(batch), {[{change, index}], size}}
        else
          {:cont, {[{change, index} | batch], bytes + size}}
        end
      end,
      fn
        {[], _bytes} -> {:cont, {[], 0}}
        {batch, _bytes} -> {:cont, Enum.reverse(batch), {[], 0}}
      end
    )
    |> Enum.map(fn [{_change, offset} | _] = batch -> {Enum.map(batch, &elem(&1, 0)), offset} end)
  end

  defp post!(url, token, batch, offset, totals) do
    options =
      [
        json: %{changes: batch},
        auth: {:bearer, token},
        receive_timeout: 60_000
      ] ++ Application.get_env(:tayori, :ingest_req_options, [])

    case Req.post(url, options) do
      {:ok, %{status: status, body: %{"added" => added, "existing" => existing} = body}}
      when status in [200, 201, 422] ->
        errors = Enum.map(body["errors"] || [], &Map.update!(&1, "index", fn i -> i + offset end))

        %{
          added: totals.added + added,
          existing: totals.existing + existing,
          errors: totals.errors ++ errors
        }

      {:ok, %{status: status, body: body}} ->
        Mix.raise("#{url} answered #{status}: #{inspect(body)}")

      {:error, exception} ->
        Mix.raise("Cannot reach #{url}: #{Exception.message(exception)}")
    end
  end

  defp report(changes, totals) do
    Mix.shell().info(line("Sent #{length(changes)} changes", totals))

    for %{"index" => index, "errors" => errors} <- totals.errors do
      ref = changes |> Enum.at(index, %{}) |> Map.get(:ref)

      messages =
        Enum.map_join(errors, "; ", fn {field, list} -> "#{field} #{Enum.join(list, ", ")}" end)

      Mix.shell().error("#{ref}: #{messages}")
    end

    if totals.errors != [] do
      Mix.raise("#{length(totals.errors)} changes were not added")
    end
  end

  defp line(name, counts) do
    "#{name}: #{counts.added} new, #{counts.existing} there already" <>
      if counts.errors == [], do: "", else: ", #{length(counts.errors)} invalid"
  end
end
