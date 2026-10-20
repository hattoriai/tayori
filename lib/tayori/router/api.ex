defmodule Tayori.Router.API do
  @moduledoc """
  The news as JSON, mounted with `tayori_api/2` (imported with
  `Tayori.Router`). See `Tayori.API` for the routes, and the
  [Any frontend](any_frontend.md) guide.

  Mount it behind a pipeline that accepts JSON and has the app's session,
  so that the resolver finds the app's user in the conn's assigns. For
  the `:embed` feature, mount it again, behind a pipeline with no session
  (see `Tayori.Embed`).
  """

  use PhoenixMountable, otp_app: :tayori, macro: :tayori_api

  options(
    resolver: [
      type: :atom,
      required: true,
      verify: {:behaviour, Tayori.Resolver},
      doc: "The app's `Tayori.Resolver`, which reads the reader from the conn."
    ],
    page: [
      type: :string,
      doc:
        "The path or address of the public page, for the `url` of each entry. By default, the `tayori_page` of the same router."
    ]
  )

  routes do
    get "/", Tayori.API, :index
    get "/unread", Tayori.API, :unread, as: :unread
    post "/seen", Tayori.API, :seen, as: :seen
    get "/categories", Tayori.API, :categories, as: :categories
    get "/announcement", Tayori.API, :announcement, as: :announcement
    post "/announcement/:id/dismiss", Tayori.API, :dismiss, as: :dismiss
    get "/ui/button", Tayori.API, :ui_button, as: :ui_button
    get "/ui/panel", Tayori.API, :ui_panel, as: :ui_panel
    post "/ui/panel", Tayori.API, :ui_open, as: :ui_open
    get "/ui/announcement", Tayori.API, :ui_announcement, as: :ui_announcement
    get "/tayori.js", Tayori.API, :asset, as: :script
    get "/tayori.css", Tayori.API, :asset, as: :stylesheet
    get "/tayori-sumi.css", Tayori.API, :asset, as: :sumi_stylesheet
    post "/:id/reactions", Tayori.API, :react, as: :reactions
    post "/uploads/:token", Tayori.API, :upload, as: :upload
    get "/:slug", Tayori.API, :show, as: :entry
    options "/", Tayori.API, :preflight, as: :preflight
    options "/*path", Tayori.API, :preflight, as: :preflight
  end
end
