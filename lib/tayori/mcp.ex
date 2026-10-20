if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP do
    @moduledoc """
    An MCP server for the news, built on [Sake](https://hexdocs.pm/sake):
    an MCP client (Claude Code, Claude Desktop, an agent) reads the news
    and the inbox, adds what shipped, drafts entries, writes them in each
    language with their screenshots, and publishes them when it is asked
    to, as the admin of the app it acts for.

    Compiled only when the app depends on `:sake`. Mount it in the app's
    own Sake server, next to the servers of its other libraries, or serve
    it on an endpoint of its own:

        defmodule MyAppWeb.MCP do
          use Sake.Server, name: "my-app", version: "1.0.0"
          mount Tayori.MCP, prefix: "tayori"
        end

        # or, in the router
        sake_endpoint "/news/mcp", server: Tayori.MCP, auth: true

    ## Scopes

      * `tayori:read` - read the news, the drafts, the inbox and the
        categories.
      * `tayori:write` - add changes to the inbox, draft, write, publish
        and unpublish entries, and upload their images.

    The app's subject module gives them to its roles (`scopes_for/2`), and
    the app's `Tayori.Resolver` decides as in the admin: `:all` may do what
    the token's scopes allow, `:read_only` only read. Nobody may use the
    server until the `:mcp` option of `Tayori.Config` names the resolver:

        {Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub,
         mcp: [resolver: MyAppWeb.TayoriResolver]}

    Nothing is published but by `publish_entry`, and nothing is deleted.
    See the [MCP](mcp.md) guide.
    """

    use Sake.Server,
      name: "tayori",
      version: Mix.Project.config()[:version],
      instructions: """
      Tayori is this app's product news: entries (a changelog), each in the app's
      languages, read in the app, on a public page and in emails. What shipped waits in
      the inbox as changes, until it becomes an entry.

      The work goes inbox, draft, review, publish:

      1. Read what waits with list_changes (state "new"); add what shipped and is not
         there with add_change, and put aside what readers need not know with hide_change.
      2. Make a draft of the new public changes with draft_entry, or write one yourself
         with create_entry. Entries are written in Markdown.
      3. Read it with get_entry, and improve it with update_entry: the title, a summary,
         the body, the other languages (missing_locales), the categories
         (list_categories). For a screenshot, use request_upload and send the file with
         the curl command it gives, then put the Markdown it answers in the body.
      4. Publish only when the person asks you to: publish_entry, now or at a time.
         A draft is never published otherwise. A publication reaches the app's readers,
         and may send emails: say what you publish, and give its URL.
      """

    scope "tayori:read", "Read the news and the inbox"
    scope "tayori:write", "Write, draft and publish the news"

    tools [
      Tayori.MCP.Tools.ListEntries,
      Tayori.MCP.Tools.GetEntry,
      Tayori.MCP.Tools.ListChanges,
      Tayori.MCP.Tools.ListCategories,
      Tayori.MCP.Tools.AddChange,
      Tayori.MCP.Tools.HideChange,
      Tayori.MCP.Tools.DraftEntry,
      Tayori.MCP.Tools.CreateEntry,
      Tayori.MCP.Tools.UpdateEntry,
      Tayori.MCP.Tools.PublishEntry,
      Tayori.MCP.Tools.UnpublishEntry,
      Tayori.MCP.Tools.RequestUpload,
      Tayori.MCP.Tools.UploadImage
    ]

    middleware :after_list, [Tayori.MCP.Access]
  end
end
