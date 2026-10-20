defmodule Tayori.Router.API do
  @moduledoc """
  The news as JSON, mounted with `tayori_api/2` (imported with
  `Tayori.Router`). See `Tayori.API` for the routes, and the
  [Any frontend](any_frontend.md) guide.

  Mount it behind a pipeline that accepts JSON and has the app's session,
  so that the resolver finds the app's user in the conn's assigns.
  """

  use PhoenixMountable, otp_app: :tayori, macro: :tayori_api

  options(
    resolver: [
      type: :atom,
      required: true,
      verify: {:behaviour, Tayori.Resolver},
      doc: "The app's `Tayori.Resolver`, which reads the reader from the conn."
    ],
    page: [type: :string, doc: "The path of the public page, for the `url` of each entry."]
  )

  routes do
    get "/", Tayori.API, :index
    get "/unread", Tayori.API, :unread, as: :unread
    post "/seen", Tayori.API, :seen, as: :seen
    get "/:slug", Tayori.API, :show, as: :entry
  end
end
