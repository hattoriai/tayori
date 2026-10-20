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
    * `:inbox` - where the changes of the inbox come from, and what they
      say when they do not (see `Tayori.Inbox` and the Automation guide):
        * `:sources` - `{module, opts}` of `Tayori.Source`, such as
          `{Tayori.Sources.Changelog, path: {:my_app, "priv/CHANGELOG.md"}}`
          or `{Tayori.Sources.Fragments, path: {:my_app, "priv/news"}}`
          (`[]`).
        * `:ingest_on_start` - read the sources when the app starts,
          which is a deploy's new code (`true`).
        * `:audience` - of a change that does not say: `"public"` or
          `"internal"` (`"public"`).
        * `:kinds` - the category of each kind of change a source names,
          `%{"added" => "new", "fixed" => "fixed"}` (`%{}`). A kind that
          is a category's key is that category.
        * `:github` - how a merged pull request's labels speak to the
          inbox (see `Tayori.GitHub`): `:label_prefix` (`"changelog:"`),
          and `:only_labeled`, to take only the pull requests with a
          label of the prefix (`false`).
    * `:digest` - when the inbox becomes an entry (see `Tayori.Digest`):
        * `:every` - `:manual` (the admin asks), `:ingest` (each time
          changes come), `{:weekly, day}` (`:monday` ... `:sunday`;
          `:weekly` is Monday), `:monthly` (the first day), or
          `{:days, n}`, n days after the last (`:manual`).
        * `:at` - the time of day of a scheduled digest, UTC
          (`~T[09:00:00]`).
        * `:publish` - `:draft`, for the admin to read and publish, or
          `:publish`, at once (`:draft`).
        * `:minimum` - the changes a scheduled digest needs (`1`): with
          fewer, they wait for the next.
        * `:translate` - with AI, the entry in the other `:locales` too,
          translated by the model (`false`).
    * `:emails` - when the subscribers get the entries to email (the
      `:subscriptions` feature; see `Tayori.Subscribers`):
        * `:every` - `:each`, an email for each entry when it is
          published, or an email of the entries of a period:
          `{:weekly, day}` (`:weekly` is Monday), `:monthly` (the first
          day), or `{:days, n}` (`:each`).
        * `:at` - the time of day of an email of a period, UTC
          (`~T[09:00:00]`).
    * `:mcp` - the MCP server, `Tayori.MCP`, for an app that serves it
      with Sake (see the [MCP](mcp.md) guide):
        * `:resolver` - the app's `Tayori.Resolver`, which says what the
          principal of a request may do (`c:Tayori.Resolver.resolve_access/1`)
          and who writes (`c:Tayori.Resolver.author/1`), as in the admin.
          Without it, nobody may use the server.
        * `:upload_url` - the address of the uploads route of `tayori_api`,
          whole (`"https://atelier.app/api/news/uploads"`), where an agent
          sends its screenshots. Without it, an agent sends only small
          images, in the call.
        * `:storage` - the `Kotoba.Storage` of the uploads (Kotoba's own
          config when not given), the one of the admin's editor.
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
    :inbox,
    :digest,
    :emails,
    :embed,
    :mcp,
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
          inbox: inbox(),
          digest: digest(),
          emails: emails(),
          embed: %{origins: [String.t(), ...], max_age: pos_integer()} | nil,
          mcp: mcp() | nil,
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
      inbox: inbox(Keyword.get(opts, :inbox, [])),
      digest: digest(Keyword.get(opts, :digest, [])),
      emails: emails(Keyword.get(opts, :emails, [])),
      embed: embed(opts[:embed]),
      mcp: mcp(opts[:mcp]),
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

  @doc false
  # An option checked as `new/1` checks it, for a config changed in tests.
  def option(:inbox, value), do: inbox(value)
  def option(:digest, value), do: digest(value)
  def option(:emails, value), do: emails(value)
  def option(:mcp, value), do: mcp(value)
  def option(:oban, %{name: _, queue: _} = oban), do: oban
  def option(:oban, value), do: oban(value)
  def option(_key, value), do: value

  @typedoc "The `:inbox` option, checked."
  @type inbox :: %{
          sources: [{module(), keyword()}],
          ingest_on_start: boolean(),
          audience: String.t(),
          kinds: %{String.t() => String.t()},
          github: %{label_prefix: String.t(), only_labeled: boolean()}
        }

  @typedoc "The `:digest` option, checked."
  @type digest :: %{
          every: :manual | :ingest | :monthly | {:weekly, atom()} | {:days, pos_integer()},
          at: Time.t(),
          publish: :draft | :publish,
          minimum: pos_integer(),
          translate: boolean()
        }

  @typedoc "The `:emails` option, checked."
  @type emails :: %{
          every: :each | :monthly | {:weekly, atom()} | {:days, pos_integer()},
          at: Time.t()
        }

  @days ~w(monday tuesday wednesday thursday friday saturday sunday)a

  defp inbox(opts) when is_list(opts) do
    sources = Keyword.get(opts, :sources, [])

    unless is_list(sources) and Enum.all?(sources, &source?/1) do
      raise ArgumentError,
            ":sources of :inbox must be a list of {module, opts} of Tayori.Source, got: #{inspect(sources)}"
    end

    audience = Keyword.get(opts, :audience, "public")

    unless audience in Tayori.Change.audiences() do
      raise ArgumentError, ~s(:audience of :inbox must be "public" or "internal")
    end

    kinds = Keyword.get(opts, :kinds, %{})

    unless is_map(kinds) and Enum.all?(kinds, fn {k, v} -> is_binary(k) and is_binary(v) end) do
      raise ArgumentError, ":kinds of :inbox must be a map of strings, got: #{inspect(kinds)}"
    end

    %{
      sources: Enum.map(sources, &source/1),
      ingest_on_start: Keyword.get(opts, :ingest_on_start, true) == true,
      audience: audience,
      kinds: Map.new(kinds, fn {k, v} -> {String.downcase(k), v} end),
      github: github(Keyword.get(opts, :github, []))
    }
  end

  defp inbox(other),
    do: raise(ArgumentError, ":inbox must be a keyword list, got: #{inspect(other)}")

  defp github(opts) when is_list(opts) do
    prefix = Keyword.get(opts, :label_prefix, "changelog:")

    unless is_binary(prefix) and prefix != "" do
      raise ArgumentError, ":label_prefix of :github must be a string, got: #{inspect(prefix)}"
    end

    %{
      label_prefix: String.downcase(prefix),
      only_labeled: Keyword.get(opts, :only_labeled, false) == true
    }
  end

  defp github(other),
    do: raise(ArgumentError, ":github of :inbox must be a keyword list, got: #{inspect(other)}")

  defp source?({module, opts}) when is_atom(module) and is_list(opts), do: true
  defp source?(module) when is_atom(module), do: true
  defp source?(_other), do: false

  defp source(module) when is_atom(module), do: source({module, []})

  defp source({module, opts}) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :changes, 1) do
      raise ArgumentError, "#{inspect(module)} is not a Tayori.Source"
    end

    {module, opts}
  end

  defp digest(opts) when is_list(opts) do
    every = weekly(Keyword.get(opts, :every, :manual))

    unless every in [:manual, :ingest] or period?(every) do
      raise ArgumentError,
            ":every of :digest must be :manual, :ingest, :monthly, {:weekly, day} or {:days, n}, got: #{inspect(every)}"
    end

    at = Keyword.get(opts, :at, ~T[09:00:00])
    unless match?(%Time{}, at), do: raise(ArgumentError, ":at of :digest must be a Time")

    publish = Keyword.get(opts, :publish, :draft)

    unless publish in [:draft, :publish] do
      raise ArgumentError, ":publish of :digest must be :draft or :publish"
    end

    minimum = Keyword.get(opts, :minimum, 1)

    unless is_integer(minimum) and minimum > 0 do
      raise ArgumentError, ":minimum of :digest must be a positive integer"
    end

    translate = Keyword.get(opts, :translate, false)

    unless is_boolean(translate) do
      raise ArgumentError, ":translate of :digest must be true or false"
    end

    %{every: every, at: at, publish: publish, minimum: minimum, translate: translate}
  end

  defp digest(other),
    do: raise(ArgumentError, ":digest must be a keyword list, got: #{inspect(other)}")

  defp emails(opts) when is_list(opts) do
    every = weekly(Keyword.get(opts, :every, :each))

    unless every == :each or period?(every) do
      raise ArgumentError,
            ":every of :emails must be :each, {:weekly, day}, :monthly or {:days, n}, got: #{inspect(every)}"
    end

    at = Keyword.get(opts, :at, ~T[09:00:00])
    unless match?(%Time{}, at), do: raise(ArgumentError, ":at of :emails must be a Time")

    %{every: every, at: at}
  end

  defp emails(other),
    do: raise(ArgumentError, ":emails must be a keyword list, got: #{inspect(other)}")

  defp weekly(:weekly), do: {:weekly, :monday}
  defp weekly(every), do: every

  defp period?(:monthly), do: true
  defp period?({:weekly, day}), do: day in @days
  defp period?({:days, n}), do: is_integer(n) and n > 0
  defp period?(_other), do: false
  @typedoc "The `:mcp` option, checked."
  @type mcp :: %{
          resolver: module() | nil,
          upload_url: String.t() | nil,
          storage: module() | nil
        }

  defp mcp(nil), do: nil

  defp mcp(opts) when is_list(opts) do
    case Keyword.split(opts, [:resolver, :upload_url, :storage]) do
      {opts, []} ->
        %{
          resolver: mcp_resolver(opts[:resolver]),
          upload_url: upload_url(opts[:upload_url]),
          storage: opts[:storage]
        }

      {_opts, other} ->
        raise ArgumentError,
              ":mcp takes :resolver, :upload_url and :storage, got: #{inspect(Keyword.keys(other))}"
    end
  end

  defp mcp(other),
    do: raise(ArgumentError, ":mcp must be a keyword list, got: #{inspect(other)}")

  defp mcp_resolver(nil), do: nil

  defp mcp_resolver(resolver) when is_atom(resolver) do
    unless Code.ensure_loaded?(resolver) and function_exported?(resolver, :resolve_access, 1) do
      raise ArgumentError,
            ":resolver of :mcp must be a Tayori.Resolver, got: #{inspect(resolver)}"
    end

    resolver
  end

  defp mcp_resolver(other),
    do: raise(ArgumentError, ":resolver of :mcp must be a module, got: #{inspect(other)}")

  defp upload_url(nil), do: nil

  defp upload_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, query: nil}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        String.trim_trailing(url, "/")

      _ ->
        raise ArgumentError,
              ":upload_url of :mcp must be an http(s) address, with no query, got: #{inspect(url)}"
    end
  end

  defp upload_url(other),
    do: raise(ArgumentError, ":upload_url of :mcp must be a string, got: #{inspect(other)}")

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

  # One character as a reader sees it (👍, ❤️, 👨‍👩‍👧, 🇵🇹), with no letters,
  # digits or spaces.
  defp emoji?(value) do
    is_binary(value) and byte_size(value) <= 64 and String.length(value) == 1 and
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
