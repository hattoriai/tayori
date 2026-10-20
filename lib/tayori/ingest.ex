defmodule Tayori.Ingest do
  @moduledoc """
  Changes sent to the inbox over HTTP, by CI or another service:
  `POST /changes` of the JSON API (`Tayori.API`), with the ingest token.

      curl -X POST https://myapp.com/api/machines/news/changes \\
        -H "authorization: Bearer $TAYORI_INGEST_TOKEN" \\
        -H "content-type: application/json" \\
        -d '{"changes": [{"ref": "pr-1234", "title": "Exports in two clicks", "kind": "added"}]}'

  The body is `{"changes": [...]}`, or `{"change": {...}}` for one: the
  attributes `Tayori.Inbox.add/2` takes, with `"source"` `"api"` when
  they do not say. The answer counts them:

      {"added": 1, "existing": 0, "errors": [{"index": 2, "errors": {"title": ["can't be blank"]}}]}

  It is a 201 when any change was new, a 200 when none was, and a 422
  when none could be added. A request has at most 500 changes, and a
  body of at most a megabyte (a 413). Without the token, or with another,
  it is a 401; while no token was ever made, a 404.

  There is one token. The admin makes it, and sees it once: Tayori keeps
  only its SHA-256, and compares in constant time. Making a new one
  revokes the old.

  `mix tayori.ingest` sends a changelog and fragments from CI. The
  [Automation](automation.md) guide mounts the API for machines.
  """

  alias Tayori.Settings

  @setting "ingest"
  @prefix "tyi_"

  @doc """
  Makes the ingest token, in place of any other, and returns it. It is
  shown once: Tayori keeps only its hash.
  """
  @spec new_token() :: {:ok, String.t()}
  def new_token do
    token = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    Settings.put(@setting, %{
      "sha256" => hash(token),
      "created_at" => DateTime.to_iso8601(DateTime.utc_now())
    })

    {:ok, token}
  end

  @doc "Whether there is an ingest token."
  @spec token?() :: boolean()
  def token?, do: is_binary(Settings.get(@setting)["sha256"])

  @doc "Revokes the ingest token: the requests with it get a 404."
  @spec revoke_token() :: :ok
  def revoke_token, do: Settings.put(@setting, %{})

  @doc """
  Whether a token is the ingest token, compared in constant time. False
  when there is none.
  """
  @spec verify(String.t() | nil) :: boolean()
  def verify(token) when is_binary(token) do
    case Settings.get(@setting)["sha256"] do
      sha256 when is_binary(sha256) -> Plug.Crypto.secure_compare(hash(token), sha256)
      nil -> false
    end
  end

  def verify(_token), do: false

  defp hash(token), do: :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)
end
