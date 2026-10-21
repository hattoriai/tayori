defmodule Tayori.Router.Mail do
  @moduledoc """
  The addresses of the campaigns' letters, mounted with `tayori_mail/2`
  (imported with `Tayori.Router`): the page to unsubscribe, the
  one-click unsubscribe of mail clients, and the mail providers'
  webhooks. See `Tayori.Campaigns.Mount` for the routes, and how to
  mount it.
  """

  use PhoenixMountable,
    otp_app: :tayori,
    macro: :tayori_mail,
    assets:
      {PhoenixMountable.Assets.Embedded,
       css: ["priv/static/tayori.css"],
       sumi: ["priv/static/tayori.css", "priv/static/tayori-sumi.css"]}

  options(
    theme: [
      type: {:in, [:tayori, :sumi]},
      default: :tayori,
      doc: "The theme of the page to unsubscribe."
    ]
  )

  routes do
    get "/unsubscribe/:token", Tayori.Campaigns.Mount, :unsubscribe
    post "/unsubscribe/:token", Tayori.Campaigns.Mount, :unsubscribe_post, as: :unsubscribe_post
    post "/webhooks/:provider", Tayori.Campaigns.Mount, :webhook, as: :webhook
  end
end
