defmodule Tayori.Config do
  @moduledoc """
  The options of Tayori, given to its child in the app's supervision tree:

      children = [
        MyApp.Repo,
        {Phoenix.PubSub, name: MyApp.PubSub},
        {Tayori,
         repo: MyApp.Repo,
         pubsub: MyApp.PubSub,
         secret_key_base: Application.fetch_env!(:my_app, MyAppWeb.Endpoint)[:secret_key_base],
         locales: ["en", "pt-PT"]},
        MyAppWeb.Endpoint
      ]

  Options:

    * `:repo` - the app's Ecto repo, where the entries are (required).
    * `:pubsub` - the app's `Phoenix.PubSub`, on which the app's pages
      hear of a new entry as it is published (required).
    * `:vault` - the app's `Cloak.Vault` (`MyApp.Vault`), which encrypts
      the AI key of the admin with the app's own keys, and rotates them
      with the app's other secrets. Without it, `:secret_key_base`.
    * `:secret_key_base` - the secret the AI key is encrypted with when
      there is no `:vault`. With neither, the admin cannot keep a key, and
      has no AI.
    * `:locales` - the languages the entries are written in, the first the
      one every entry has (`["en"]`).
    * `:prefix` - the schema of the tables, in PostgreSQL.
    * `:notifier` - a module of the `Tayori.Notifier` behaviour, told of
      each entry once, when it is published.
    * `:features` - the extras the app wants, none by default; the
      changelog itself is always there. A feature that is off has no
      admin page, no route, no element and no process:
        * `:reactions` - readers react to an entry with an emoji.
        * `:announcements` - an entry shown as a popup, a toast or a
          banner in the app, until a date.
        * `:analytics` - the views of each entry, by where it was read.
        * `:subscriptions` - readers subscribe by email on the public
          page, and an entry can be sent to them.
        * `:webhooks` - webhooks, Slack and Discord, told of each entry.
        * `:embed` - the news on another origin than the app's, with a
          reader's signed token (`Tayori.Embed`).
    * `:mailer` - the app's `Swoosh.Mailer`, which sends the emails of
      the `:subscriptions` feature (required with it).
    * `:email_from` - who the emails are from: `{"Atelier", "news@atelier.app"}`
      or an address (required with `:subscriptions`).
    * `:page_url` - the address of the public page
      (`"https://atelier.app/changelog"`), for the links of the emails
      (required with `:subscriptions`).
    * `:reactions` - the emoji readers react with
      (`["👍", "🎉", "❤️", "🚀", "👀"]`).
    * `:oban` - the app's Oban, which then sends what a publication sends
      (the emails, the webhooks, the call to the `:notifier`) as jobs:
      `oban: Oban`, or `oban: [name: MyApp.Oban, queue: :news]` for
      another instance or queue (`:default`). The queue must be one the
      app runs. Without it, they are sent by tasks in the node, as
      `Tayori.Jobs` explains.
    * `:embed` - the sites of the `:embed` feature (required with it):
        * `:origins` - the origins the JSON API answers, each a scheme
          and a host, with a port if not the default
          (`["https://www.atelier.app"]`): no path, no wildcard.
        * `:max_age` - how long a reader token is valid, in seconds
          (86400, a day).

      The feature also needs `:secret_key_base`, which signs the tokens.
  """

  @features [:reactions, :announcements, :analytics, :subscriptions, :webhooks, :embed]
  @reactions ["👍", "🎉", "❤️", "🚀", "👀"]

  @enforce_keys [:repo, :pubsub]
  defstruct [
    :repo,
    :pubsub,
    :secret_key_base,
    :vault,
    :prefix,
    :notifier,
    :mailer,
    :email_from,
    :page_url,
    :oban,
    :embed,
    locales: ["en"],
    features: [],
    reactions: @reactions
  ]

  @type t :: %__MODULE__{
          repo: module(),
          pubsub: atom(),
          secret_key_base: String.t() | nil,
          vault: module() | nil,
          prefix: String.t() | nil,
          notifier: module() | nil,
          mailer: module() | nil,
          email_from: String.t() | {String.t(), String.t()} | nil,
          page_url: String.t() | nil,
          oban: %{name: term(), queue: atom()} | nil,
          embed: %{origins: [String.t(), ...], max_age: pos_integer()} | nil,
          locales: [String.t(), ...],
          features: [feature()],
          reactions: [String.t(), ...]
        }

  @typedoc "An extra the app can turn on."
  @type feature ::
          :reactions | :announcements | :analytics | :subscriptions | :webhooks | :embed

  @key {Tayori, :config}

  @doc "Builds the config from the options of the child, and checks them."
  @spec new(keyword()) :: t()
  def new(opts) do
    repo = Keyword.get(opts, :repo) || raise ArgumentError, "Tayori needs the :repo option"
    pubsub = Keyword.get(opts, :pubsub) || raise ArgumentError, "Tayori needs the :pubsub option"
    features = features(Keyword.get(opts, :features, []))
    check_dependencies(features, opts)

    %__MODULE__{
      oban: oban(opts[:oban]),
      embed: embed(opts[:embed]),
      mailer: opts[:mailer],
      email_from: opts[:email_from],
      page_url: opts[:page_url] && String.trim_trailing(opts[:page_url], "/"),
      features: features,
      reactions: reactions(Keyword.get(opts, :reactions, @reactions)),
      repo: repo,
      pubsub: pubsub,
      secret_key_base: secret_key_base(opts[:secret_key_base]),
      vault: opts[:vault],
      prefix: opts[:prefix],
      notifier: opts[:notifier],
      locales: locales(Keyword.get(opts, :locales, ["en"]))
    }
  end

  defp locales(locales) do
    unless is_list(locales) and locales != [] and Enum.all?(locales, &is_binary/1) do
      raise ArgumentError, ":locales must be a list of language tags, got: #{inspect(locales)}"
    end

    locales
  end

  defp secret_key_base(secret) do
    if secret != nil and (not is_binary(secret) or byte_size(secret) < 32) do
      raise ArgumentError, ":secret_key_base must be a string of at least 32 bytes"
    end

    secret
  end

  defp features(features) do
    unless is_list(features) and Enum.all?(features, &(&1 in @features)) do
      raise ArgumentError,
            ":features must be a list of #{inspect(@features)}, got: #{inspect(features)}"
    end

    Enum.uniq(features)
  end

  defp reactions(reactions) do
    unless is_list(reactions) and reactions != [] and Enum.all?(reactions, &emoji?/1) do
      raise ArgumentError, ":reactions must be a list of emoji, got: #{inspect(reactions)}"
    end

    reactions
  end

  # The features that send something need the app's mailer, or Req.
  defp check_dependencies(features, opts) do
    if :subscriptions in features do
      for key <- [:mailer, :email_from, :page_url], opts[key] == nil do
        raise ArgumentError, "the :subscriptions feature needs the #{inspect(key)} option"
      end

      unless Code.ensure_loaded?(Swoosh.Email) do
        raise ArgumentError, "the :subscriptions feature needs the :swoosh dependency"
      end
    end

    if :webhooks in features and not Code.ensure_loaded?(Req) do
      raise ArgumentError, "the :webhooks feature needs the :req dependency"
    end

    if :embed in features do
      if opts[:embed] == nil do
        raise ArgumentError,
              "the :embed feature needs the :embed option, with the origins of the sites: " <>
                ~s(embed: [origins: ["https://www.example.com"]])
      end

      if opts[:secret_key_base] == nil do
        raise ArgumentError,
              "the :embed feature needs the :secret_key_base option, which signs the reader tokens"
      end
    end
  end

  defp embed(nil), do: nil

  defp embed(opts) when is_list(opts) do
    case Keyword.split(opts, [:origins, :max_age]) do
      {opts, []} ->
        %{origins: origins(opts[:origins]), max_age: max_age(Keyword.get(opts, :max_age, 86_400))}

      {_opts, other} ->
        raise ArgumentError,
              ":embed takes :origins and :max_age, got: #{inspect(Keyword.keys(other))}"
    end
  end

  defp embed(other) do
    raise ArgumentError,
          ~s(:embed must be [origins: ["https://www.example.com"]], got: #{inspect(other)})
  end

  defp origins(origins) when is_list(origins) and origins != [] do
    origins
    |> Enum.map(fn origin ->
      case Tayori.Embed.normalize_origin(origin) do
        {:ok, origin} ->
          origin

        :error ->
          raise ArgumentError,
                "each origin of :embed is a scheme and a host, with a port if not the default " <>
                  "(\"https://www.example.com\"): no path, no wildcard; got: #{inspect(origin)}"
      end
    end)
    |> Enum.uniq()
  end

  defp origins(other) do
    raise ArgumentError,
          ":origins of :embed must be a list of the sites' origins, got: #{inspect(other)}"
  end

  defp max_age(seconds) when is_integer(seconds) and seconds > 0, do: seconds

  defp max_age(other) do
    raise ArgumentError,
          ":max_age of :embed must be a number of seconds, got: #{inspect(other)}"
  end

  defp oban(nil), do: nil
  defp oban(name) when is_atom(name), do: oban(name: name)

  defp oban(opts) when is_list(opts) do
    unless Code.ensure_loaded?(Oban) do
      raise ArgumentError, "the :oban option needs the :oban dependency"
    end

    name = Keyword.get(opts, :name, Oban)
    queue = Keyword.get(opts, :queue, :default)

    unless is_atom(queue) do
      raise ArgumentError, ":queue of the :oban option must be an atom, got: #{inspect(queue)}"
    end

    %{name: name, queue: queue}
  end

  defp oban(other) do
    raise ArgumentError,
          ":oban must be the name of an Oban instance or [name: ..., queue: ...], got: #{inspect(other)}"
  end

  @doc "Keeps the config for the whole node."
  @spec put(t()) :: :ok
  def put(%__MODULE__{} = config), do: :persistent_term.put(@key, config)

  @doc """
  The config of the running Tayori. Raises when Tayori is not in the app's
  supervision tree.
  """
  @spec get() :: t()
  def get do
    case :persistent_term.get(@key, nil) do
      nil ->
        raise "Tayori is not started: add {Tayori, repo: ..., pubsub: ...} to your supervision tree"

      config ->
        config
    end
  end

  # An emoji is a short string with no letters, digits or spaces.
  defp emoji?(value) do
    is_binary(value) and value != "" and byte_size(value) <= 16 and
      not String.match?(value, ~r/[\p{L}\p{N}\s]/u)
  end

  @doc "All the extras an app can turn on."
  @spec features() :: [feature()]
  def features, do: @features

  @doc "Whether the app turned an extra on."
  @spec feature?(t(), feature()) :: boolean()
  def feature?(%__MODULE__{features: features}, feature) when feature in @features,
    do: feature in features

  @doc "The language every entry has."
  @spec default_locale(t()) :: String.t()
  def default_locale(%__MODULE__{locales: [locale | _]}), do: locale
end
