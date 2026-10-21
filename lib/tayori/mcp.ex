if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP do
    @moduledoc """
    An MCP server for what the app has to say to its people, built on
    [Sake](https://hexdocs.pm/sake): an MCP client (Claude Code, Claude
    Desktop, an agent) reads the news and the inbox, adds what shipped,
    drafts entries, writes them in each language with their screenshots,
    and publishes them when it is asked to; with the campaigns, it reads
    the audience, saves segments, writes sequences and broadcasts, tries
    their letters, and starts or sends them when it is asked to; as the
    admin of the app it acts for.

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
      * `tayori:campaigns:read` - read the audience, the segments and the
        campaigns, and preview letters.
      * `tayori:campaigns:write` - save segments, write campaigns, their
        steps and letters, send test letters, pause campaigns.
      * `tayori:campaigns:send` - start a sequence, take people into it and
        send a broadcast: email the app's people.

    The tools of a module that is off (the `:modules` of `Tayori.Config`)
    are not listed. The app's subject module gives the scopes to its roles
    (`scopes_for/2`), and the app's `Tayori.Resolver` decides as in the
    admin: `:all` may do what the token's scopes allow, `:read_only` only
    read. Nobody may use the server until the `:mcp` option of
    `Tayori.Config` names the resolver:

        {Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub,
         mcp: [resolver: MyAppWeb.TayoriResolver]}

    Nothing is published but by `publish_entry`, nobody is emailed but by
    `start_campaign`, `enroll_people`, `send_broadcast` and
    `send_test_letter`, and nothing is deleted but a campaign's step
    (`remove_step`). See the
    [MCP](mcp.md) guide.
    """

    use Sake.Server,
      name: "tayori",
      version: Mix.Project.config()[:version],
      instructions: """
      Tayori is what this app has to say to its people. It has one or two modules, and
      you see the tools of those it has.

      The news (list_entries and the rest): entries (a changelog), each in the app's
      languages, read in the app, on a public page and in emails. What shipped waits in
      the inbox as changes, until it becomes an entry. The work goes inbox, draft,
      review, publish:

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

      When this app has campaigns (list_campaigns and the rest): letters by email to each
      of its people, by what they did. A sequence is a series of letters at times after a
      person enters it (on an event, or by hand), until its goal; a broadcast is one
      letter to everyone in an audience. Who gets what is said with conditions on the
      app's people. The work goes audience, segment, campaign, letters, preview, send:

      1. Read the audience with list_audience: the attributes, their operators, the
         events, the segments. Write conditions only with those.
      2. Try a condition with preview_segment (how many people, who, in words); save it
         with save_segment when it will be used again.
      3. Make the campaign with create_campaign, a draft (its audience, and for a
         sequence its trigger, goal, gap and days), and change it with update_campaign.
      4. Write the letters in Markdown: add_step for each letter of a sequence, at its
         time after entry, with a skip_if when it is not always wanted; update_step for
         a broadcast's one letter and for the other languages. Merge tags such as
         {{first_name|there}} take each person's values.
      5. Read it back with get_campaign (problems says what keeps it from starting),
         read a letter as a person gets it with preview_letter, and send a test to the
         person with send_test_letter.
      6. Start a sequence (start_campaign) or send a broadcast (send_broadcast) only when
         the person asks you to, and say first how many people it reaches (get_campaign
         gives the audience's count). These email real people and cannot be taken back.
         A sequence started by hand takes people in with enroll_people, by their ids or
         by a condition or a segment (say first how many enter). pause_campaign stops a
         sequence, or a scheduled broadcast.
      """

    scope "tayori:read", "Read the news and the inbox"
    scope "tayori:write", "Write, draft and publish the news"
    scope "tayori:campaigns:read", "Read the audience and the campaigns"
    scope "tayori:campaigns:write", "Write segments, campaigns and their letters"
    scope "tayori:campaigns:send", "Start campaigns, take people in and send broadcasts"

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
      Tayori.MCP.Tools.UploadImage,
      Tayori.MCP.Tools.Campaigns.ListAudience,
      Tayori.MCP.Tools.Campaigns.PreviewSegment,
      Tayori.MCP.Tools.Campaigns.ListCampaigns,
      Tayori.MCP.Tools.Campaigns.GetCampaign,
      Tayori.MCP.Tools.Campaigns.PreviewLetter,
      Tayori.MCP.Tools.Campaigns.SaveSegment,
      Tayori.MCP.Tools.Campaigns.CreateCampaign,
      Tayori.MCP.Tools.Campaigns.UpdateCampaign,
      Tayori.MCP.Tools.Campaigns.AddStep,
      Tayori.MCP.Tools.Campaigns.UpdateStep,
      Tayori.MCP.Tools.Campaigns.RemoveStep,
      Tayori.MCP.Tools.Campaigns.SendTestLetter,
      Tayori.MCP.Tools.Campaigns.PauseCampaign,
      Tayori.MCP.Tools.Campaigns.StartCampaign,
      Tayori.MCP.Tools.Campaigns.EnrollPeople,
      Tayori.MCP.Tools.Campaigns.SendBroadcast
    ]

    middleware :after_list, [Tayori.MCP.Access]
  end
end
