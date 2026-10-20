defmodule Mix.Tasks.Tayori.ReleaseCheck do
  @shortdoc "Checks that priv/static holds the six bundle files and nothing else"

  @moduledoc """
  Checks the built files before a release of Tayori.

      $ mix tayori.release_check

  This task is for work on Tayori itself; the `release` alias runs it
  after `mix tayori.build` and before `mix hex.publish`. In any project
  but Tayori, it stops with an error. It fails when:

    * one of the six bundle files (`tayori.esm.js`, `tayori.cjs.js`,
      `tayori.css`, `tayori-sumi.css`, `tayori-admin.js` and
      `tayori-admin.css`) is missing from `priv/static`,
      or is empty (the empty files that CI makes are not a build);
    * `priv/static` holds any other file or directory;
    * the `version` of `package.json` is not the version of `mix.exs`.
  """

  use Mix.Task

  @static "priv/static"
  @files ~w(tayori.esm.js tayori.cjs.js tayori.css tayori-sumi.css tayori-admin.js tayori-admin.css)

  @impl Mix.Task
  def run(_args) do
    config = Mix.Project.config()
    ensure_tayori!(config)
    version = config[:version]

    case check(@static, "package.json", version) do
      :ok ->
        Mix.shell().info(
          "#{@static} holds the six bundle files, and nothing else, and package.json has version #{version}"
        )

      {:error, problems} ->
        Mix.raise("""
        Tayori is not ready for a release:

        #{Enum.map_join(problems, "\n", &("  * " <> &1))}

        Build with `mix tayori.build` (it empties #{@static} first); keep the \
        version of package.json equal to the version of mix.exs.\
        """)
    end
  end

  @doc false
  @spec ensure_tayori!(keyword()) :: :ok
  def ensure_tayori!(config) do
    if config[:app] == :tayori do
      :ok
    else
      Mix.raise(
        "mix tayori.release_check is for work on Tayori itself; it checks the files of a Tayori release"
      )
    end
  end

  @doc false
  @spec check(Path.t(), Path.t(), String.t()) :: :ok | {:error, [String.t()]}
  def check(static, package_json, version) do
    entries =
      case File.ls(static) do
        {:ok, entries} -> entries
        {:error, _reason} -> []
      end

    problems =
      Enum.flat_map(@files, &bundle_problems(static, &1, entries)) ++
        Enum.map(Enum.sort(entries -- @files), &"#{static}/#{&1} is not a bundle file") ++
        version_problems(package_json, version)

    if problems == [], do: :ok, else: {:error, problems}
  end

  defp bundle_problems(static, file, entries) do
    path = Path.join(static, file)

    cond do
      file not in entries -> ["#{path} is missing"]
      not File.regular?(path) -> ["#{path} is not a file"]
      File.stat!(path).size == 0 -> ["#{path} is empty"]
      true -> []
    end
  end

  defp version_problems(package_json, version) do
    with {:ok, source} <- File.read(package_json),
         {:ok, %{"version" => ^version}} <- JSON.decode(source) do
      []
    else
      _other -> ["the version of #{package_json} is not #{version}"]
    end
  end
end
