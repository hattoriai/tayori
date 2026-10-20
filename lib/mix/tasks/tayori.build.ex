defmodule Mix.Tasks.Tayori.Build do
  @shortdoc "Builds the bundles and the style sheets into priv/static"

  @moduledoc """
  Builds the bundles and style sheets of Tayori into `priv/static`.

      $ mix tayori.build

  This task is for work on Tayori itself. An application that uses Tayori
  gets the built files in the Hex package and does not run this task: in
  any project but Tayori, the task stops with an error before it changes
  a file.

  The task:

    1. Runs `npm ci` in `assets/` when `assets/node_modules` is missing or
       `assets/package-lock.json` changed since the last install.
    2. Empties `priv/static`, so that it holds only the files of this
       build.
    3. Runs esbuild (the `esbuild` Mix package) with the `:tayori_esm` and
       `:tayori_cjs` profiles (the news in the app) and `:tayori_admin`
       (the admin, with Phoenix, LiveView, Kotoba and Koyomi from `deps/`).
    4. Copies `assets/css/tayori.css`, `assets/css/tayori-sumi.css` and
       `assets/css/tayori-admin.css` to `priv/static/`, with the Sumi fonts
       (`assets/css/sumi-fonts.css`) in place of the marker of
       `tayori-sumi.css`.

  After the task, `priv/static` holds exactly these six files, which are
  the files of the Hex package.

  It needs `npm` on the path and the `:esbuild` dependency, which is
  available in the `:dev` environment.
  """

  use Mix.Task

  @compile {:no_warn_undefined, Esbuild}

  @assets "assets"
  @static "priv/static"
  @lock_hash "node_modules/.tayori-lock-sha256"
  @profiles [:tayori_esm, :tayori_cjs, :tayori_admin]
  @stylesheets ["tayori.css", "tayori-sumi.css", "tayori-admin.css"]

  @impl Mix.Task
  def run(_args) do
    ensure_tayori!(Mix.Project.config())
    Mix.Task.run("loadpaths")

    unless Code.ensure_loaded?(Esbuild) do
      Mix.raise("""
      mix tayori.build needs the :esbuild dependency, which is available in \
      the :dev environment. Run it as `MIX_ENV=dev mix tayori.build`.\
      """)
    end

    {:ok, _apps} = Application.ensure_all_started(:esbuild)

    install_packages()
    File.rm_rf!(@static)
    File.mkdir_p!(@static)
    Enum.each(@profiles, &bundle/1)
    Enum.each(@stylesheets, &copy_stylesheet/1)

    Mix.shell().info("Tayori assets are in #{@static}/")
  end

  # The task empties priv/static, so it must never run in an application.
  @doc false
  @spec ensure_tayori!(keyword()) :: :ok
  def ensure_tayori!(config) do
    if config[:app] == :tayori do
      :ok
    else
      Mix.raise(
        "mix tayori.build is for work on Tayori itself; an app gets the built files in the Hex package"
      )
    end
  end

  defp install_packages do
    lock = Path.join(@assets, "package-lock.json")
    stamp = Path.join(@assets, @lock_hash)
    hash = lock |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    if File.dir?(Path.join(@assets, "node_modules")) and File.read(stamp) == {:ok, hash} do
      Mix.shell().info("assets/node_modules is up to date")
    else
      npm = System.find_executable("npm") || Mix.raise("mix tayori.build needs npm on the path")
      Mix.shell().info("Running npm ci in assets/")

      case System.cmd(npm, ["ci", "--prefix", @assets], into: IO.stream(), stderr_to_stdout: true) do
        {_output, 0} -> File.write!(stamp, hash)
        {_output, status} -> Mix.raise("npm ci exited with status #{status}")
      end
    end
  end

  defp bundle(profile) do
    case Esbuild.install_and_run(profile, []) do
      0 -> :ok
      status -> Mix.raise("esbuild #{profile} exited with status #{status}")
    end
  end

  # The Sumi fonts go into the Sumi style sheet, where its marker is, so
  # that the source stays readable.
  defp copy_stylesheet(name) do
    fonts = File.read!(Path.join([@assets, "css", "sumi-fonts.css"]))

    css =
      [@assets, "css", name]
      |> Path.join()
      |> File.read!()
      |> String.replace("/* @tayori-sumi-fonts */", fonts)

    File.write!(Path.join(@static, name), css)
  end
end
