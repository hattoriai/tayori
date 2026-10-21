defmodule Tayori.Campaigns.Provider do
  @moduledoc """
  A mail provider's webhooks, for the campaigns: what it says of the
  letters it was given, delivered, bounced or complained of. Tayori has
  two, `Tayori.Campaigns.Providers.Resend` and
  `Tayori.Campaigns.Providers.Postmark`; an app writes its own for
  another, and names it in the `:providers` of `:campaigns` with its
  options:

      providers: [ses: {MyApp.TayoriSES, topic_arn: "arn:aws:sns:..."}]

  The webhook is then `POST {campaigns url}/webhooks/ses`. Tayori reads
  the request's body, as it was sent, and gives it to `c:verify/3`;
  then decodes it as JSON and gives it to `c:events/1`. What follows is
  the same for every provider: a hard bounce or a complaint means the
  address is not written to again (`Tayori.Campaigns.suppress/3`), and
  the letter (by `provider_id`, the id the mailer gave it) is marked so;
  a delivery changes nothing; a soft bounce is nothing. The same event
  twice is the same.
  """

  @typedoc "What the provider says of a letter."
  @type event :: %{
          type: :delivered | :bounced | :complained,
          email: String.t(),
          provider_id: String.t() | nil,
          hard?: boolean()
        }

  @doc """
  Whether the request is the provider's: its headers (the conn), its body
  as it was sent, and the options of the provider in the config, as a
  map. `:ok`, else `:error` (a 401).
  """
  @callback verify(conn :: Plug.Conn.t(), raw_body :: binary(), opts :: map()) :: :ok | :error

  @doc "The events of a payload, the body decoded as JSON."
  @callback events(payload :: map()) :: [event()]
end
