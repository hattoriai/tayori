defmodule Tayori.API.Machines do
  @moduledoc false
  # The routes of the JSON API for machines, not readers: the changes CI
  # sends (Tayori.Ingest), and GitHub's webhook (Tayori.GitHub). They read
  # no session and no reader, and answer no CORS: each request carries
  # its own proof, a token or a signature.

  @behaviour Plug

  import Plug.Conn

  alias Tayori.{GitHub, Inbox, Ingest}

  require Logger

  # A request's body, and its changes, at most.
  @max_body 1_000_000
  @max_changes 500
  # GitHub's payloads can be larger: a pull request's description.
  @max_github_body 10_000_000

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, :changes) do
    cond do
      not Ingest.token?() -> json(conn, 404, %{error: "not_found"})
      not Ingest.verify(bearer(conn)) -> unauthorized(conn)
      true -> changes(conn)
    end
  end

  def call(conn, :github) do
    if GitHub.secret?(), do: github(conn), else: json(conn, 404, %{error: "not_found"})
  end

  # ── The changes of CI ───────────────────────────────────────────

  defp changes(conn) do
    with {:ok, params, conn} <- params(conn),
         {:ok, changes} <- change_list(params, conn) do
      {valid, invalid} = split(changes)
      result = Inbox.add_many(Enum.map(valid, &elem(&1, 0)), source: "api")
      Tayori.Digest.after_ingest(result.added)

      errors =
        Enum.map(result.errors, fn {i, changeset} ->
          {valid |> Enum.at(i) |> elem(1), errors(changeset)}
        end) ++ invalid

      errors = errors |> Enum.sort() |> Enum.map(fn {i, e} -> %{index: i, errors: e} end)

      status =
        cond do
          result.added > 0 -> 201
          changes != [] and length(errors) == length(changes) -> 422
          true -> 200
        end

      json(conn, status, %{added: result.added, existing: result.existing, errors: errors})
    else
      {:error, status, error, conn} -> json(conn, status, %{error: error})
    end
  end

  # The body, as the endpoint parsed it or not.
  defp params(%{body_params: %Plug.Conn.Unfetched{}} = conn) do
    with {:ok, body, conn} <- read(conn, @max_body) do
      case JSON.decode(body) do
        {:ok, %{} = params} -> {:ok, params, conn}
        _ -> {:error, 400, "invalid_json", conn}
      end
    end
  end

  defp params(conn) do
    if too_large?(conn),
      do: {:error, 413, "too_large", conn},
      else: {:ok, conn.body_params, conn}
  end

  defp read(conn, max) do
    case read_body(conn, length: max) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _body, conn} -> {:error, 413, "too_large", conn}
      {:error, _reason} -> {:error, 400, "invalid_body", conn}
    end
  end

  defp too_large?(conn) do
    case get_req_header(conn, "content-length") do
      [length | _] -> match?({n, ""} when n > @max_body, Integer.parse(length))
      [] -> false
    end
  end

  defp change_list(%{"changes" => changes}, conn) when is_list(changes) do
    if length(changes) > @max_changes,
      do: {:error, 413, "too_many_changes", conn},
      else: {:ok, changes}
  end

  defp change_list(%{"change" => change}, _conn), do: {:ok, [change]}
  defp change_list(_params, conn), do: {:error, 400, "no_changes", conn}

  # The changes that are objects, with their index, and the others.
  defp split(changes) do
    changes
    |> Enum.with_index()
    |> Enum.split_with(fn {change, _i} -> is_map(change) end)
    |> then(fn {valid, invalid} ->
      {valid, Enum.map(invalid, fn {_change, i} -> {i, %{change: ["must be an object"]}} end)}
    end)
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp bearer(conn) do
    with [header | _] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme) do
      String.trim(token)
    else
      _ -> nil
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="tayori"))
    |> json(401, %{error: "unauthorized"})
  end

  # ── GitHub's webhook ────────────────────────────────────────────

  defp github(conn) do
    with {:ok, body, conn} <- raw_body(conn),
         :ok <- signed(conn, body),
         {:ok, payload} <- payload(conn, body) do
      event = conn |> get_req_header("x-github-event") |> List.first("")

      case GitHub.handle(event, payload) do
        {:ok, changes} -> add(conn, event, changes)
        :ignore -> json(conn, 202, %{ignored: event})
      end
    else
      {:error, status, error, conn} -> json(conn, status, %{error: error})
    end
  end

  defp add(conn, event, changes) do
    result = Inbox.add_many(changes, source: "github")
    Tayori.Digest.after_ingest(result.added)

    errors =
      for {i, changeset} <- result.errors do
        ref = Enum.at(changes, i)[:ref]
        errors = errors(changeset)
        Logger.warning("Tayori could not add #{ref} of GitHub (#{event}): #{inspect(errors)}")
        %{index: i, errors: errors}
      end

    json(conn, 200, %{added: result.added, existing: result.existing, errors: errors})
  end

  # The body as GitHub signed it: read here, or kept by GitHub.read_body/2
  # when the endpoint's parsers read it.
  defp raw_body(%{body_params: %Plug.Conn.Unfetched{}} = conn), do: read(conn, @max_github_body)

  defp raw_body(%{private: %{tayori_raw_body: iodata}} = conn),
    do: {:ok, IO.iodata_to_binary(iodata), conn}

  defp raw_body(conn) do
    Logger.error(
      "Tayori cannot check GitHub's signature: the endpoint read the body before it. " <>
        "Give Plug.Parsers `body_reader: {Tayori.GitHub, :read_body, []}`."
    )

    {:error, 500, "no_raw_body", conn}
  end

  defp signed(conn, body) do
    signature = conn |> get_req_header("x-hub-signature-256") |> List.first()

    case GitHub.verify(body, signature) do
      :ok -> :ok
      {:error, _reason} -> {:error, 401, "invalid_signature", conn}
    end
  end

  # A JSON payload, or a form's `payload` field (GitHub's other content
  # type).
  defp payload(conn, body) do
    json =
      case get_req_header(conn, "content-type") do
        ["application/x-www-form-urlencoded" <> _ | _] -> URI.decode_query(body)["payload"]
        _ -> body
      end

    case is_binary(json) && JSON.decode(json) do
      {:ok, %{} = payload} -> {:ok, payload}
      _ -> {:error, 400, "invalid_json", conn}
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, JSON.encode!(body))
    |> halt()
  end
end
