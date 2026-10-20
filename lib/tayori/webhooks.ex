defmodule Tayori.Webhooks do
  @moduledoc """
  Tells other places of each entry when it is published: the `:webhooks`
  feature. The admin adds them in Settings:

    * a webhook - a POST of the entry as JSON, signed with its secret
      (`x-tayori-signature: sha256=<hex HMAC of the body>`);
    * Slack - a message to an incoming webhook URL;
    * Discord - a message to a channel webhook URL.

  Their URLs and secrets are kept encrypted, as the AI key is (a `:vault`
  or the `:secret_key_base` of `Tayori.Config`). A failed delivery is
  tried again (`Tayori.Jobs`), unless the place refused it for good.

  A webhook gets every entry, for everyone or not; Slack and Discord get
  the entries for everyone, which are public.
  """

  alias Tayori.{Config, Entry, Settings}
  # Req is an optional dependency, needed with the :webhooks feature.
  @compile {:no_warn_undefined, Req}

  @setting "webhooks"
  @kinds ~w(webhook slack discord)

  @typedoc "A place told of the entries."
  @type hook :: %{
          required(String.t()) => String.t()
        }

  @doc "The kinds of places."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc """
  The places, without their secrets: `%{"id", "kind", "name", "host"}`,
  where `host` shows where it goes without the secret part of the URL.
  """
  @spec list() :: [map()]
  def list do
    Enum.map(hooks(), fn hook ->
      %{
        "id" => hook["id"],
        "kind" => hook["kind"],
        "name" => hook["name"],
        "host" => URI.parse(hook["url"]).host
      }
    end)
  end

  defp hooks do
    case Settings.secret(@setting) do
      nil -> []
      json -> JSON.decode!(json)
    end
  end

  @doc """
  Adds a place: a kind, a name, an https URL and, for a webhook, a secret
  to sign with (one is made when none is given). Returns the secret.
  """
  @spec add(String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t() | nil} | {:error, atom()}
  def add(kind, name, url, secret \\ nil) do
    cond do
      not Settings.secrets?() -> {:error, :no_secrets}
      kind not in @kinds -> {:error, :unknown_kind}
      not https?(url) -> {:error, :not_https}
      String.trim(name) == "" -> {:error, :no_name}
      true -> put_hook(kind, String.trim(name), url, secret)
    end
  end

  defp put_hook(kind, name, url, secret) do
    secret =
      if kind == "webhook",
        do: secret || Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    hook = %{
      "id" => Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false),
      "kind" => kind,
      "name" => String.slice(name, 0, 80),
      "url" => url,
      "secret" => secret
    }

    save(hooks() ++ [hook])
    {:ok, secret}
  end

  @doc "Removes a place."
  @spec remove(String.t()) :: :ok
  def remove(id) do
    save(Enum.reject(hooks(), &(&1["id"] == id)))
    :ok
  end

  defp save(hooks) do
    Settings.put(@setting, %{"count" => length(hooks)}, JSON.encode!(hooks))
  end

  defp https?(url) do
    match?(%URI{scheme: "https", host: host} when host not in [nil, ""], URI.parse(url))
  end

  @doc false
  # The places to tell of an entry, from the scheduler's announcement.
  @spec targets(Config.t(), Ecto.UUID.t()) :: [String.t()]
  def targets(%Config{} = config, entry_id) do
    with true <- Config.feature?(config, :webhooks),
         %Entry{} = entry <- Tayori.Entries.get(entry_id) do
      for hook <- hooks(), hook["kind"] == "webhook" or entry.segments == [], do: hook["id"]
    else
      _none -> []
    end
  end

  @doc false
  # Tells one place of an entry, once. A place removed since, or an entry
  # deleted since, is nothing to tell.
  @spec deliver(Config.t(), Ecto.UUID.t(), String.t()) :: :ok | {:error, term()}
  def deliver(%Config{} = config, entry_id, hook_id) do
    with %{} = hook <- Enum.find(hooks(), &(&1["id"] == hook_id)),
         %Entry{} = entry <- Tayori.Entries.get(entry_id) do
      post(hook, payload(config, hook, entry))
    else
      _gone -> :ok
    end
  end

  @doc false
  # Whether a failed delivery is worth another try: not when the place
  # refused it for good (a 4xx other than a timeout or too many requests).
  @spec retry?(term()) :: boolean()
  def retry?({:status, status}) when status in 400..499, do: status in [408, 425, 429]
  def retry?(_reason), do: true

  @doc false
  # The name of a place, for the logs.
  @spec name(String.t()) :: String.t()
  def name(hook_id) do
    case Enum.find(hooks(), &(&1["id"] == hook_id)) do
      %{"name" => name} -> name
      nil -> hook_id
    end
  end

  @doc "Sends a test message to a place, and returns how it went."
  @spec test(String.t()) :: :ok | {:error, term()}
  def test(id) do
    config = Config.get()

    case Enum.find(hooks(), &(&1["id"] == id)) do
      nil -> {:error, :not_found}
      hook -> post(hook, payload(config, hook, nil))
    end
  end

  defp post(hook, body) do
    json = JSON.encode!(body)

    headers =
      [{"content-type", "application/json"}] ++
        if hook["kind"] == "webhook" do
          signature =
            :crypto.mac(:hmac, :sha256, hook["secret"], json) |> Base.encode16(case: :lower)

          [{"x-tayori-signature", "sha256=" <> signature}]
        else
          []
        end

    case Req.post(hook["url"],
           body: json,
           headers: headers,
           retry: false,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # The message of each kind of place. With no entry, a test.
  defp payload(config, %{"kind" => "webhook"}, entry) do
    %{
      "event" => if(entry, do: "entry.published", else: "test"),
      "entry" => entry && json(config, entry)
    }
  end

  defp payload(config, %{"kind" => "slack"}, entry) do
    %{"text" => line(config, entry)}
  end

  defp payload(config, %{"kind" => "discord"}, entry) do
    %{"content" => line(config, entry)}
  end

  defp line(_config, nil), do: "Tayori is connected: the news will come here."

  defp line(config, entry) do
    t = Entry.translation(entry, nil, config.locales)
    url = config.page_url && config.page_url <> "/" <> entry.slug

    [t.title, t.summary, url]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp json(config, entry) do
    %{
      "id" => entry.id,
      "slug" => entry.slug,
      "categories" => entry.categories,
      "segments" => entry.segments,
      "publishedAt" => entry.published_at && DateTime.to_iso8601(entry.published_at),
      "url" => config.page_url && config.page_url <> "/" <> entry.slug,
      "translations" =>
        Map.new(entry.translations, fn t ->
          {t.locale,
           %{
             "title" => t.title,
             "summary" => t.summary,
             "html" => t.body && t.body.html,
             "text" => t.body && t.body.text
           }}
        end)
    }
  end
end
