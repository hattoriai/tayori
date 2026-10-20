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
    * `:secret_key_base` - the secret the AI key of the admin is encrypted
      with. Without it, the admin cannot keep a key, and has no AI.
    * `:locales` - the languages the entries are written in, the first the
      one every entry has (`["en"]`).
    * `:prefix` - the schema of the tables, in PostgreSQL.
    * `:notifier` - a module of the `Tayori.Notifier` behaviour, told of
      each entry once, when it is published.
  """

  @enforce_keys [:repo, :pubsub]
  defstruct [:repo, :pubsub, :secret_key_base, :prefix, :notifier, locales: ["en"]]

  @type t :: %__MODULE__{
          repo: module(),
          pubsub: atom(),
          secret_key_base: String.t() | nil,
          prefix: String.t() | nil,
          notifier: module() | nil,
          locales: [String.t(), ...]
        }

  @key {Tayori, :config}

  @doc "Builds the config from the options of the child, and checks them."
  @spec new(keyword()) :: t()
  def new(opts) do
    repo = Keyword.get(opts, :repo) || raise ArgumentError, "Tayori needs the :repo option"
    pubsub = Keyword.get(opts, :pubsub) || raise ArgumentError, "Tayori needs the :pubsub option"
    locales = Keyword.get(opts, :locales, ["en"])

    unless is_list(locales) and locales != [] and Enum.all?(locales, &is_binary/1) do
      raise ArgumentError, ":locales must be a list of language tags, got: #{inspect(locales)}"
    end

    secret = opts[:secret_key_base]

    if secret != nil and (not is_binary(secret) or byte_size(secret) < 32) do
      raise ArgumentError, ":secret_key_base must be a string of at least 32 bytes"
    end

    %__MODULE__{
      repo: repo,
      pubsub: pubsub,
      secret_key_base: secret,
      prefix: opts[:prefix],
      notifier: opts[:notifier],
      locales: locales
    }
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

  @doc "The language every entry has."
  @spec default_locale(t()) :: String.t()
  def default_locale(%__MODULE__{locales: [locale | _]}), do: locale
end
