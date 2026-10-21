defmodule Tayori.Campaigns.WebhooksTest do
  use TayoriTest.DataCase

  import TayoriTest.Signing

  alias Tayori.Campaigns
  alias Tayori.Campaigns.{Delivery, Webhooks}
  alias Tayori.Campaigns.Providers.{Postmark, Resend}

  defp conn(headers) do
    Enum.reduce(headers, Plug.Test.conn(:post, "/letters/webhooks/x"), fn {key, value}, conn ->
      Plug.Conn.put_req_header(conn, key, value)
    end)
  end

  defp delivery!(provider_id, email) do
    campaign = sequence!([step(0, "Welcome")])
    [step] = campaign.steps
    config = Tayori.Config.get()

    config.repo.insert!(%Delivery{
      campaign_id: campaign.id,
      step_id: step.id,
      person: "person:#{System.unique_integer([:positive])}",
      email: email,
      status: "sent",
      provider_id: provider_id
    })
  end

  defp status(delivery) do
    config = Tayori.Config.get()
    config.repo.get!(Delivery, delivery.id).status
  end

  test "Resend: a Svix signature, of the body, with the secret, within five minutes" do
    opts = %{secret: resend_secret()}
    body = ~s({"type":"email.delivered"})

    assert :ok = Resend.verify(conn(svix_headers(body)), body, opts)
    assert :error = Resend.verify(conn(svix_headers(body)), body <> " ", opts)

    assert :error =
             Resend.verify(
               conn(svix_headers(body, System.system_time(:second), "other")),
               body,
               opts
             )

    assert :error =
             Resend.verify(
               conn(svix_headers(body, System.system_time(:second) - 301)),
               body,
               opts
             )

    assert :error =
             Resend.verify(
               conn(svix_headers(body, System.system_time(:second) + 301)),
               body,
               opts
             )

    assert :ok =
             Resend.verify(
               conn(svix_headers(body, System.system_time(:second) - 290)),
               body,
               opts
             )

    assert :error = Resend.verify(conn([]), body, opts)
    assert :error = Resend.verify(conn(svix_headers(body)), body, %{secret: "whsec_not base64!"})

    [{_, id}, {_, ts}, _] = svix_headers(body)

    assert :error =
             Resend.verify(
               conn([{"svix-id", id}, {"svix-timestamp", ts}, {"svix-signature", "v2,abc"}]),
               body,
               opts
             )
  end

  test "Resend's events" do
    data = %{"email_id" => "re_1", "to" => ["ada@app.test"]}

    assert [%{type: :delivered, email: "ada@app.test", provider_id: "re_1"}] =
             Resend.events(%{"type" => "email.delivered", "data" => data})

    assert [%{type: :bounced, hard?: true}] =
             Resend.events(%{"type" => "email.bounced", "data" => data})

    assert [%{type: :bounced, hard?: false}] =
             Resend.events(%{
               "type" => "email.bounced",
               "data" => Map.put(data, "bounce", %{"type" => "Transient"})
             })

    assert [%{type: :complained}] = Resend.events(%{"type" => "email.complained", "data" => data})
    assert Resend.events(%{"type" => "email.opened", "data" => data}) == []
    assert Resend.events(%{"type" => "email.bounced", "data" => %{}}) == []
    assert Resend.events(%{}) == []
  end

  test "Postmark: basic authentication, and its events" do
    opts = %{username: "tayori", password: "s3cret"}
    assert :ok = Postmark.verify(conn([basic("tayori", "s3cret")]), "", opts)
    assert :error = Postmark.verify(conn([basic("tayori", "wrong")]), "", opts)
    assert :error = Postmark.verify(conn([basic("other", "s3cret")]), "", opts)
    assert :error = Postmark.verify(conn([{"authorization", "Basic !!"}]), "", opts)
    assert :error = Postmark.verify(conn([]), "", opts)

    assert [%{type: :delivered, email: "ada@app.test", provider_id: "pm-1"}] =
             Postmark.events(%{
               "RecordType" => "Delivery",
               "Recipient" => "ada@app.test",
               "MessageID" => "pm-1"
             })

    assert [%{type: :bounced, hard?: true}] =
             Postmark.events(%{
               "RecordType" => "Bounce",
               "Type" => "HardBounce",
               "Email" => "ada@app.test"
             })

    assert [%{type: :bounced, hard?: false}] =
             Postmark.events(%{
               "RecordType" => "Bounce",
               "Type" => "SoftBounce",
               "Email" => "ada@app.test"
             })

    assert [%{type: :complained}] =
             Postmark.events(%{"RecordType" => "SpamComplaint", "Email" => "ada@app.test"})

    assert Postmark.events(%{"RecordType" => "Open"}) == []
  end

  for_each_repo do
    setup :campaigns

    test "a hard bounce or a complaint suppresses the address and marks its letter" do
      bounced = delivery!("re_1", "ada@app.test")
      complained = delivery!("re_2", "grace@app.test")
      soft = delivery!("re_3", "alan@app.test")
      config = Tayori.Config.get()

      event = fn type, id, to, extra ->
        %{"type" => type, "data" => Map.merge(%{"email_id" => id, "to" => [to]}, extra)}
      end

      assert 1 =
               Webhooks.handle(
                 config,
                 Resend,
                 event.("email.delivered", "re_1", "ada@app.test", %{})
               )

      assert status(bounced) == "sent"

      Webhooks.handle(config, Resend, event.("email.bounced", "re_1", "Ada@App.test", %{}))
      Webhooks.handle(config, Resend, event.("email.bounced", "re_1", "ada@app.test", %{}))
      assert status(bounced) == "bounced"
      assert Campaigns.suppressed?("ada@app.test", "product")
      assert Campaigns.suppressed?("ada@app.test", "marketing")

      Webhooks.handle(config, Resend, event.("email.complained", "re_2", "grace@app.test", %{}))
      assert status(complained) == "complained"
      assert Campaigns.suppressed?("grace@app.test", "product")
      # A bounce after a complaint does not take it back.
      Webhooks.handle(config, Resend, event.("email.bounced", "re_2", "grace@app.test", %{}))
      assert status(complained) == "complained"

      Webhooks.handle(
        config,
        Resend,
        event.("email.bounced", "re_3", "alan@app.test", %{"bounce" => %{"type" => "Transient"}})
      )

      assert status(soft) == "sent"
      refute Campaigns.suppressed?("alan@app.test", "product")

      # An event of no letter of Tayori's still suppresses.
      Webhooks.handle(config, Resend, event.("email.complained", "re_9", "edsger@app.test", %{}))
      assert Campaigns.suppressed?("edsger@app.test", "product")
    end

    test "a provider by name: built-in or the app's own, never an atom made" do
      config =
        put_config(Tayori.Config.get(),
          campaigns: [
            audience: TayoriTest.Audience,
            url: "https://app.test/letters",
            from: "rui@app.test",
            providers: [
              resend: [secret: resend_secret()],
              custom: {TayoriTest.CustomProvider, token: "t0k"}
            ]
          ]
        )

      assert {Resend, %{secret: _}} = Webhooks.provider(config, "resend")
      assert {TayoriTest.CustomProvider, %{token: "t0k"}} = Webhooks.provider(config, "custom")
      assert Webhooks.provider(config, "postmark") == nil
      assert Webhooks.provider(config, "never-an-atom-#{System.unique_integer()}") == nil
    end
  end
end
