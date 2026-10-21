defmodule Tayori.Campaigns.Providers.Postmark do
  @moduledoc """
  [Postmark](https://postmarkapp.com)'s webhooks, behind HTTP basic
  authentication:

      providers: [postmark: [username: "tayori", password: "..."]]

  Give Postmark the webhook's address with them:
  `https://tayori:...@example.com/letters/webhooks/postmark`. They are
  compared in constant time. The events, by `RecordType`: `Delivery`,
  `Bounce` (hard when its `Type` is `HardBounce`) and `SpamComplaint`.
  """

  @behaviour Tayori.Campaigns.Provider

  @impl true
  def verify(conn, _raw_body, %{username: username, password: password}) do
    with ["Basic " <> encoded] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, pair} <- Base.decode64(String.trim(encoded)),
         [given_user, given_password] <- String.split(pair, ":", parts: 2) do
      # Both compared, whatever the first gives, in constant time.
      user? = Plug.Crypto.secure_compare(given_user, username)
      password? = Plug.Crypto.secure_compare(given_password, password)
      if user? and password?, do: :ok, else: :error
    else
      _ -> :error
    end
  end

  def verify(_conn, _raw_body, _opts), do: :error

  @impl true
  def events(%{"RecordType" => "Delivery", "Recipient" => email} = payload)
      when is_binary(email),
      do: [%{type: :delivered, email: email, provider_id: payload["MessageID"], hard?: false}]

  def events(%{"RecordType" => "Bounce", "Email" => email} = payload) when is_binary(email) do
    [
      %{
        type: :bounced,
        email: email,
        provider_id: payload["MessageID"],
        hard?: payload["Type"] == "HardBounce"
      }
    ]
  end

  def events(%{"RecordType" => "SpamComplaint", "Email" => email} = payload)
      when is_binary(email),
      do: [%{type: :complained, email: email, provider_id: payload["MessageID"], hard?: true}]

  def events(_payload), do: []
end
