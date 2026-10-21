defmodule Tayori.Campaigns.Providers.Resend do
  @moduledoc """
  [Resend](https://resend.com)'s webhooks, signed by Svix:

      providers: [resend: [secret: "whsec_..."]]

  The secret is the webhook's signing secret, from Resend. The request
  carries `svix-id`, `svix-timestamp` and `svix-signature`: the
  signature is an HMAC-SHA256 of `"<id>.<timestamp>.<body>"` with the
  secret (base64 after `whsec_`), and a request more than five minutes
  from now is refused. The events: `email.delivered`, `email.bounced`
  (hard unless Resend says it was `Transient`) and `email.complained`.
  """

  @behaviour Tayori.Campaigns.Provider

  @tolerance 5 * 60

  @impl true
  def verify(conn, raw_body, %{secret: "whsec_" <> secret}) do
    with [id] <- Plug.Conn.get_req_header(conn, "svix-id"),
         [timestamp] <- Plug.Conn.get_req_header(conn, "svix-timestamp"),
         [signatures] <- Plug.Conn.get_req_header(conn, "svix-signature"),
         {seconds, ""} <- Integer.parse(timestamp),
         true <- abs(System.system_time(:second) - seconds) <= @tolerance,
         {:ok, key} <- Base.decode64(secret) do
      expected =
        :crypto.mac(:hmac, :sha256, key, "#{id}.#{timestamp}.#{raw_body}") |> Base.encode64()

      signatures
      |> String.split(" ", trim: true)
      |> Enum.any?(fn
        "v1," <> signature -> Plug.Crypto.secure_compare(signature, expected)
        _other -> false
      end)
      |> if(do: :ok, else: :error)
    else
      _ -> :error
    end
  end

  def verify(_conn, _raw_body, _opts), do: :error

  @impl true
  def events(%{"type" => type, "data" => %{} = data}) do
    id = data["email_id"]

    case {type, recipient(data["to"])} do
      {_type, nil} ->
        []

      {"email.delivered", email} ->
        [%{type: :delivered, email: email, provider_id: id, hard?: false}]

      {"email.bounced", email} ->
        hard? = get_in(data, ["bounce", "type"]) != "Transient"
        [%{type: :bounced, email: email, provider_id: id, hard?: hard?}]

      {"email.complained", email} ->
        [%{type: :complained, email: email, provider_id: id, hard?: true}]

      _other ->
        []
    end
  end

  def events(_payload), do: []

  defp recipient([email | _]) when is_binary(email), do: email
  defp recipient(email) when is_binary(email), do: email
  defp recipient(_to), do: nil
end
