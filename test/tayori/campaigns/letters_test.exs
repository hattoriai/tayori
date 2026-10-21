defmodule Tayori.Campaigns.LettersTest do
  use TayoriTest.DataCase

  import Swoosh.TestAssertions

  alias Tayori.Campaigns
  alias Tayori.Campaigns.{Delivery, Letters}
  alias Tayori.Recipient

  defp recipient(attrs \\ %{}) do
    struct!(
      %Recipient{
        id: "person:1",
        email: "ada@app.test",
        name: "Ada Lovelace",
        locale: "en",
        data: %{"first_name" => "Ada", "dashboard_url" => "https://app.test/dash?a=1&b=2"}
      },
      attrs
    )
  end

  defp campaign_with(letters, attrs \\ %{}) do
    {:ok, campaign} =
      Campaigns.create(Map.merge(%{"name" => "Onboarding", "kind" => "sequence"}, attrs))

    {:ok, step} = Campaigns.add_step(campaign, %{"wait" => 0, "letters" => letters})
    {Campaigns.get(campaign.id), Campaigns.get_step(step.id)}
  end

  defp letter(locale, subject, markdown, extra \\ %{}) do
    Map.merge(
      %{
        "locale" => locale,
        "subject" => subject,
        "body" => Kotoba.Content.from_markdown(markdown)
      },
      extra
    )
  end

  for_each_repo do
    setup :campaigns

    test "a letter as an email: envelope, subject, preheader, body, button, footer, headers" do
      {campaign, step} =
        campaign_with([
          letter(
            "en",
            "Welcome, {{first_name|there}}",
            "See [your board](/board) and ![A photo](/p.png).",
            %{
              "preheader" => "A minute, {{first_name}}",
              "cta_label" => "Open {{first_name}}'s board",
              "cta_url" => "{{dashboard_url}}"
            }
          )
        ])

      email = Letters.render(campaign, step, recipient())

      assert email.to == [{"Ada Lovelace", "ada@app.test"}]
      assert email.from == {"Rui at the app", "rui@app.test"}
      assert email.reply_to == nil
      assert email.subject == "Welcome, Ada"

      [unsubscribe] =
        Regex.run(~r{https://app\.test/letters/unsubscribe/[^\s"<>]+}, email.text_body)

      assert email.headers["List-Unsubscribe"] == "<#{unsubscribe}>"
      assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
      token = String.replace_prefix(unsubscribe, "https://app.test/letters/unsubscribe/", "")
      assert Letters.verify(token) == {:ok, %{email: "ada@app.test", purpose: "product"}}

      html = email.html_body

      assert html =~
               ~s(<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all">A minute, Ada</div>)

      assert html =~ ~s(href="https://app.test/board")
      assert html =~ ~s(src="https://app.test/p.png")
      assert html =~ ~s(href="https://app.test/dash?a=1&amp;b=2")
      assert html =~ "Open Ada&#39;s board"
      assert html =~ ~s(href="#{unsubscribe}")
      assert html =~ ">Rui at the app</td>"

      assert email.text_body ==
               "See your board and A photo.\n\nOpen Ada's board: https://app.test/dash?a=1&b=2\n\nUnsubscribe: #{unsubscribe}\n"
    end

    test "the campaign's sender and reply-to, else the config's" do
      {campaign, step} =
        campaign_with([letter("en", "Hi", "Hello.")], %{
          "from_name" => "Ada at the app",
          "reply_to" => "help@app.test",
          "purpose" => "marketing"
        })

      email = Letters.render(campaign, step, recipient(name: nil))
      assert email.to == [{"", "ada@app.test"}]
      assert email.from == {"Ada at the app", "rui@app.test"}
      assert email.reply_to == {"", "help@app.test"}
      assert email.html_body =~ ">Ada at the app</td>"

      [token] =
        Regex.run(~r{/unsubscribe/([^\s>]+)>}, email.headers["List-Unsubscribe"],
          capture: :all_but_first
        )

      assert {:ok, %{purpose: "marketing"}} = Letters.verify(token)

      config = Tayori.Config.get()

      put_config(config,
        campaigns: [
          audience: TayoriTest.Audience,
          url: "https://app.test/letters",
          from: "letters@app.test",
          reply_to: "rui@app.test"
        ]
      )

      {campaign, step} = campaign_with([letter("en", "Hi", "Hello.")])
      email = Letters.render(campaign, step, recipient())
      assert email.from == {"", "letters@app.test"}
      assert email.reply_to == {"", "rui@app.test"}
      assert email.html_body =~ ">app.test</td>"
    end

    test "merge tags: fallbacks, empty when unknown, escaped in the HTML" do
      {campaign, step} =
        campaign_with([
          letter(
            "en",
            "{{first_name|friend}}, {{nope}}<b>",
            "Hi {{first_name|there}} & {{nope}}{{plan|Free & co}}. [Go]({{url}}) [Search](https://app.test/?q={{first_name}})",
            %{"cta_label" => "Go", "cta_url" => "{{url}}"}
          )
        ])

      evil =
        recipient(
          data: %{"first_name" => "<script>alert(1)</script>", "url" => "javascript:alert(1)"}
        )

      email = Letters.render(campaign, step, evil)

      # The subject is text: as it is.
      assert email.subject == "<script>alert(1)</script>, <b>"
      refute email.html_body =~ "<script>"
      assert email.html_body =~ "Hi &lt;script&gt;alert(1)&lt;/script&gt; &amp; Free &amp; co."
      # An address at the start of a link must be one; after it, a part of it.
      assert email.html_body =~ ~s(<a href="" rel="noopener nofollow">Go</a>)

      assert email.html_body =~
               ~s(href="https://app.test/?q=%3Cscript%3Ealert%281%29%3C%2Fscript%3E")

      refute email.html_body =~ "javascript:"
      # No button with no address.
      refute email.text_body =~ "Go:"

      email = Letters.render(campaign, step, recipient(data: %{}))
      assert email.subject == "friend, <b>"
      assert email.text_body =~ "Hi there & Free & co."
    end

    test "the letter of the person's language, else of the language, else the first" do
      {campaign, step} =
        campaign_with([letter("en", "Hello", "Hello."), letter("pt-PT", "Olá", "Olá.")])

      assert Letters.render(campaign, step, recipient(locale: "pt-PT")).subject == "Olá"
      assert Letters.render(campaign, step, recipient(locale: "pt-BR")).subject == "Olá"
      assert Letters.render(campaign, step, recipient(locale: "fr")).subject == "Hello"
      assert Letters.render(campaign, step, recipient(locale: nil)).subject == "Hello"

      # Its footer in the letter's language.
      assert Letters.render(campaign, step, recipient(locale: "pt-BR")).text_body =~
               "Cancelar a subscrição: https://app.test/letters/unsubscribe/"

      {campaign, step} = campaign_with([letter("pt-PT", "Olá", "Olá.")])
      assert Letters.render(campaign, step, recipient(locale: "en")).subject == "Olá"
    end

    test "the tags a campaign uses, and those a person lacks" do
      {campaign, _step} =
        campaign_with([
          letter(
            "en",
            "Hi {{first_name}}",
            "Your [board]({{dashboard_url}}) and {{plan|Free}}.",
            %{"cta_label" => "{{ cta }}", "cta_url" => "https://app.test/{{path}}"}
          )
        ])

      assert Letters.tags(campaign) == ["cta", "dashboard_url", "first_name", "path", "plan"]
      assert Letters.missing(campaign, recipient()) == ["cta", "path", "plan"]
    end

    test "the token of the link to unsubscribe" do
      token = Letters.token(" Ada@App.test ", "marketing")
      assert Letters.verify(token) == {:ok, %{email: "ada@app.test", purpose: "marketing"}}
      assert Letters.verify(token <> "x") == :error
      assert Letters.verify("nope") == :error

      other =
        Phoenix.Token.sign(Tayori.Config.get().secret_key_base, "tayori unsubscribe", %{
          "e" => "a@b.c",
          "p" => "spam"
        })

      assert Letters.verify(other) == :error
    end

    test "a test letter: [Test], to an address, no delivery", %{repo: repo} do
      ada = person!(name: "Ada Lovelace")

      {campaign, step} =
        campaign_with([letter("en", "Welcome, {{first_name|there}}", "Hello {{email}}.")])

      assert {:ok, _} = Letters.send_test(campaign, step, person_id(ada), "rui@app.test")

      assert_email_sent(fn email ->
        assert email.subject == "[Test] Welcome, Ada"
        assert email.to == [{"Ada Lovelace", "rui@app.test"}]
        assert email.text_body =~ "Hello ada@app.test."

        [token] =
          Regex.run(~r{/unsubscribe/([^\s>]+)>}, email.headers["List-Unsubscribe"],
            capture: :all_but_first
          )

        assert {:ok, %{email: "rui@app.test"}} = Letters.verify(token)
      end)

      assert {:ok, _} = Letters.send_test(campaign, step, nil, "rui@app.test")
      assert_email_sent(subject: "[Test] Welcome, there", to: [{"", "rui@app.test"}])

      assert repo.aggregate(Delivery, :count) == 0
    end
  end
end
