defmodule Tayori.Router.Page do
  @moduledoc """
  The public page of the news, each entry's page, and the feeds, mounted
  with `tayori_page/2` (imported with `Tayori.Router`). See `Tayori.Page`
  for the routes, and [The public page](public_page.md) guide.
  """

  use PhoenixMountable,
    otp_app: :tayori,
    macro: :tayori_page,
    assets:
      {PhoenixMountable.Assets.Embedded,
       css: [{:kotoba, "priv/static/kotoba.css"}, "priv/static/tayori.css"],
       sumi: [
         {:kotoba, "priv/static/kotoba.css"},
         {:kotoba, "priv/static/kotoba-sumi.css"},
         "priv/static/tayori.css",
         "priv/static/tayori-sumi.css"
       ]}

  options(
    title: [
      type: :string,
      doc: "The title of the page and the feeds (\"What's new\", in the reader's language)."
    ],
    resolver: [
      type: :atom,
      verify: {:behaviour, Tayori.Resolver},
      doc:
        "The app's `Tayori.Resolver`: a reader it gives sees the entries for them too. Without it, the page shows the entries for everyone."
    ],
    layout: [
      type: {:tuple, [:atom, :atom]},
      doc: "The app's root layout, `{module, function}`, instead of Tayori's own document."
    ],
    theme: [
      type: {:in, [:tayori, :sumi]},
      default: :tayori,
      doc: "The theme of Tayori's own document."
    ],
    limit: [type: :pos_integer, default: 20, doc: "The entries of a page."],
    url: [
      type: :string,
      doc:
        "The app's address (`\"https://example.com\"`), for the links of the feeds, when the conn does not have it (behind a proxy)."
    ]
  )

  routes do
    get "/", Tayori.Page, :index
    get "/feed.xml", Tayori.Page, :atom, as: :atom
    get "/feed.json", Tayori.Page, :json, as: :json
    get "/:slug", Tayori.Page, :show, as: :entry
  end
end
