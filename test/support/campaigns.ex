defmodule TayoriTest.CustomProvider do
  @moduledoc """
  A mail provider of the app's own, as the guide writes one: its request
  carries a token, and its payload a list of events.
  """
  @behaviour Tayori.Campaigns.Provider

  @impl true
  def verify(conn, _raw_body, %{token: token}) do
    case Plug.Conn.get_req_header(conn, "x-token") do
      [^token] -> :ok
      _ -> :error
    end
  end

  @impl true
  def events(%{"events" => events}) do
    for %{"kind" => kind, "to" => email} = event <- events,
        type <- [type(kind)],
        type != nil do
      %{type: type, email: email, provider_id: event["id"], hard?: event["hard"] != false}
    end
  end

  def events(_payload), do: []

  defp type("delivered"), do: :delivered
  defp type("bounced"), do: :bounced
  defp type("complained"), do: :complained
  defp type(_kind), do: nil
end

defmodule TayoriTest.Signing do
  @moduledoc "Webhook requests as the mail providers sign them."

  @key "resend-test-signing-key"

  @doc "Resend's secret of the tests."
  def resend_secret, do: "whsec_" <> Base.encode64(@key)

  @doc "Svix's headers of a body, at a time (now, in seconds)."
  def svix_headers(body, timestamp \\ System.system_time(:second), key \\ @key) do
    id = "msg_" <> Integer.to_string(System.unique_integer([:positive]))
    signature = :crypto.mac(:hmac, :sha256, key, "#{id}.#{timestamp}.#{body}") |> Base.encode64()

    [
      {"svix-id", id},
      {"svix-timestamp", Integer.to_string(timestamp)},
      {"svix-signature", "v1,bm90IGl0 v1,#{signature}"}
    ]
  end

  @doc "A basic authorization header."
  def basic(user, password),
    do: {"authorization", "Basic " <> Base.encode64("#{user}:#{password}")}
end
