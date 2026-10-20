defmodule Tayori.SubscribersTest do
  use TayoriTest.DataCase

  import Swoosh.TestAssertions

  alias Tayori.{Mail, Subscribers}

  for_each_repo do
    setup %{config: config} do
      config =
        put_config(config,
          features: [:subscriptions],
          mailer: TayoriTest.Mailer,
          email_from: {"Atelier", "news@atelier.test"},
          page_url: "https://atelier.test/changelog"
        )

      %{config: config}
    end

    test "subscribing sends a link to confirm, to the address lowercased", %{repo: repo} do
      assert :ok = Subscribers.subscribe("  Ada@Example.COM ", "pt-PT")

      subscriber = repo.get_by!(Subscribers, email: "ada@example.com")
      assert subscriber.locale == "pt-PT"
      assert subscriber.confirmed_at == nil
      assert byte_size(subscriber.token) >= 32

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.from == {"Atelier", "news@atelier.test"}
        assert email.subject == "Confirme a sua subscrição"
        link = "https://atelier.test/changelog/subscription/confirm/" <> subscriber.token
        assert email.text_body =~ link
        assert email.html_body =~ ~s(href="#{link}")
        assert email.html_body =~ "Confirmar o meu endereço"
      end)

      assert Subscribers.counts() == %{confirmed: 0, waiting: 1}
    end

    test "an address that is not one is refused, and nothing is sent" do
      for email <- [
            "",
            "ada",
            "ada@example",
            "ada @example.com",
            String.duplicate("a", 320) <> "@x.io"
          ] do
        assert {:error, %Ecto.Changeset{}} = Subscribers.subscribe(email)
      end

      refute_email_sent()
      assert Subscribers.counts() == %{confirmed: 0, waiting: 0}
    end

    test "subscribing again while waiting sends the same link again", %{repo: repo} do
      :ok = Subscribers.subscribe("ada@example.com")
      %{token: token} = repo.get_by!(Subscribers, email: "ada@example.com")
      assert_email_sent(subject: "Confirm your subscription")

      :ok = Subscribers.subscribe("ADA@example.com")
      assert_email_sent(fn email -> assert email.text_body =~ token end)
      assert Subscribers.counts() == %{confirmed: 0, waiting: 1}
    end

    test "a confirmed address subscribing again gets nothing, and the same answer", %{
      repo: repo
    } do
      :ok = Subscribers.subscribe("ada@example.com")
      assert_email_sent()
      %{token: token} = repo.get_by!(Subscribers, email: "ada@example.com")
      {:ok, _} = Subscribers.confirm(token)

      assert :ok = Subscribers.subscribe("ada@example.com")
      refute_email_sent()
    end

    test "confirming takes the token of the link, once or again", %{repo: repo} do
      :ok = Subscribers.subscribe("ada@example.com")
      %{token: token} = repo.get_by!(Subscribers, email: "ada@example.com")

      assert {:ok, %{confirmed_at: %DateTime{} = at}} = Subscribers.confirm(token)
      assert {:ok, %{confirmed_at: again}} = Subscribers.confirm(token)
      assert DateTime.compare(again, at) == :eq
      assert Subscribers.confirm("nope") == :error
      assert Subscribers.counts() == %{confirmed: 1, waiting: 0}
    end

    test "unsubscribing deletes the address, and an unknown token is fine", %{repo: repo} do
      :ok = Subscribers.subscribe("ada@example.com")
      %{token: token} = repo.get_by!(Subscribers, email: "ada@example.com")

      assert :ok = Subscribers.unsubscribe("nope")
      assert Subscribers.counts() == %{confirmed: 0, waiting: 1}
      assert :ok = Subscribers.unsubscribe(token)
      assert Subscribers.counts() == %{confirmed: 0, waiting: 0}
      assert Subscribers.confirm(token) == :error
    end

    test "counts: the confirmed subscribers and those waiting", %{repo: repo} do
      for email <- ~w(a@x.io b@x.io c@x.io), do: :ok = Subscribers.subscribe(email)
      {:ok, _} = Subscribers.confirm(repo.get_by!(Subscribers, email: "b@x.io").token)

      assert Subscribers.counts() == %{confirmed: 1, waiting: 2}
    end

    test "the email of an entry: links whole, in the subscriber's language, with a way out", %{
      config: config
    } do
      entry =
        entry!("Exports", %{
          published_at: minutes(-1),
          translations: [
            %{
              locale: "en",
              title: "Exports",
              summary: "In two clicks",
              body:
                Kotoba.Content.from_markdown(
                  "See [the docs](/docs/exports) and [elsewhere](https://elsewhere.test/x)."
                )
            },
            %{
              locale: "pt-PT",
              title: "Exportações <rápidas>",
              summary: "Em dois cliques",
              body: Kotoba.Content.from_markdown("Veja [a ajuda](/docs/exports).")
            }
          ]
        })

      {:ok, entry} =
        Entries.put_cover_map(entry, %{"url" => "/uploads/cover.png", "alt" => "A <chart>"})

      entry = Entries.get!(entry.id)
      subscriber = %Subscribers{email: "ada@example.com", locale: "pt-PT", token: "tok"}
      email = Mail.entry(config, entry, subscriber)

      assert email.to == [{"", "ada@example.com"}]
      assert email.from == {"Atelier", "news@atelier.test"}
      assert email.subject == "Exportações <rápidas>"

      unsubscribe = "https://atelier.test/changelog/subscription/unsubscribe/tok"
      assert email.headers["List-Unsubscribe"] == "<#{unsubscribe}>"
      assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"

      link = "https://atelier.test/changelog/exports?ref=email"
      assert email.text_body =~ "Exportações <rápidas>"
      assert email.text_body =~ "Em dois cliques"
      assert email.text_body =~ "Veja a ajuda."
      assert email.text_body =~ "Ler online: " <> link
      assert email.text_body =~ "Cancelar a subscrição: " <> unsubscribe

      assert email.html_body =~ "Exportações &lt;rápidas&gt;"
      assert email.html_body =~ ~s(href="https://atelier.test/docs/exports")
      assert email.html_body =~ ~s(href="#{link}")
      assert email.html_body =~ ~s(href="#{unsubscribe}")
      assert email.html_body =~ ~s(src="https://atelier.test/uploads/cover.png")
      assert email.html_body =~ ~s(alt="A &lt;chart&gt;")
      assert email.html_body =~ "Atelier"

      english = Mail.entry(config, entry, %{subscriber | locale: nil})
      assert english.subject == "Exports"
      assert english.html_body =~ ~s(href="https://elsewhere.test/x")

      assert english.text_body =~
               "Read it online: https://atelier.test/changelog/exports?ref=email"
    end

    test "with an address alone as the sender, the emails are signed with the title", %{
      config: config
    } do
      config = put_config(config, email_from: "news@atelier.test")
      email = Mail.confirm(config, %Subscribers{email: "a@x.io", token: "t", locale: nil})

      assert email.from == {"", "news@atelier.test"}
      assert email.html_body =~ "What&#39;s new"
      refute Map.has_key?(email.headers, "List-Unsubscribe")
    end

    test "an entry is claimed once, for the confirmed subscribers, if it is for everyone", %{
      config: config,
      repo: repo
    } do
      for email <- ~w(a@x.io b@x.io), do: :ok = Subscribers.subscribe(email)
      a = repo.get_by!(Subscribers, email: "a@x.io")
      {:ok, _} = Subscribers.confirm(a.token)

      emailed = entry!("Emailed", %{email: true, published_at: minutes(-1)})
      quiet = entry!("Quiet", %{published_at: minutes(-1)})
      pro = entry!("Pro", %{email: true, segments: ["plan:pro"], published_at: minutes(-1)})

      assert Subscribers.claim_entry(config, emailed.id) == [a.id]
      assert Subscribers.claim_entry(config, emailed.id) == []
      assert %DateTime{} = Entries.get!(emailed.id).emailed_at
      assert Subscribers.claim_entry(config, quiet.id) == []
      assert Subscribers.claim_entry(config, pro.id) == []
      assert Entries.get!(pro.id).emailed_at == nil

      off = put_config(config, features: [])
      other = entry!("Off", %{email: true, published_at: minutes(-1)})
      assert Subscribers.claim_entry(off, other.id) == []
    end
  end
end
