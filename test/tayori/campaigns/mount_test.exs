defmodule Tayori.Campaigns.MountTest do
  use TayoriTest.ConnCase

  import TayoriTest.DataCase,
    only: [campaigns_config: 0, person!: 1, put_config: 2, sequence!: 1, step: 2]

  import TayoriTest.Signing

  alias Tayori.Campaigns
  alias Tayori.Campaigns.{Delivery, Letters}

  setup %{config: config} do
    campaigns =
      Keyword.update!(campaigns_config(), :campaigns, fn campaigns ->
        campaigns ++
          [
            providers: [
              resend: [secret: resend_secret()],
              postmark: [username: "tayori", password: "s3cret"],
              custom: {TayoriTest.CustomProvider, token: "t0k"}
            ]
          ]
      end)

    %{config: put_config(config, campaigns)}
  end

  defp form(conn), do: put_req_header(conn, "content-type", "application/x-www-form-urlencoded")

  describe "unsubscribing" do
    test "the page asks, in the person's language, with everything as a choice", %{conn: conn} do
      token = Letters.token("ada@app.test", "marketing")
      html = conn |> get("/letters/unsubscribe/" <> token) |> html_response(200)

      assert html =~ ~s(<html lang="en")
      assert html =~ "Stop the news and offers sent to ada@app.test?"
      assert html =~ ~s(action="/letters/unsubscribe/#{token}")
      assert html =~ ~s(name="all" value="1")
      assert html =~ "Unsubscribe from everything"
      assert html =~ ~s(<meta name="robots" content="noindex")
      assert html =~ ~r"/letters/css-[0-9a-f]{32}"
      refute html =~ "_csrf_token"

      # Of the last letter's language, or as asked.
      person = person!(name: "Ada", locale: "pt-PT")
      campaign = sequence!([step(0, "Olá")])

      Tayori.Config.get().repo.insert!(%Delivery{
        campaign_id: campaign.id,
        person: "person:#{person.id}",
        email: "ada@app.test",
        locale: "pt-PT",
        status: "sent"
      })

      html = build_conn() |> get("/letters/unsubscribe/" <> token) |> html_response(200)
      assert html =~ ~s(<html lang="pt-PT")
      assert html =~ "Deixar de receber novidades e ofertas em ada@app.test?"

      html = build_conn() |> get("/letters/unsubscribe/#{token}?lang=en") |> html_response(200)
      assert html =~ ~s(<html lang="en")

      # A language the app has not: the next guess.
      html = build_conn() |> get("/letters/unsubscribe/#{token}?lang=ja") |> html_response(200)
      assert html =~ ~s(<html lang="pt-PT")

      token = Letters.token("grace@app.test", "product")

      html =
        build_conn()
        |> put_req_header("accept-language", "pt-BR,pt;q=0.9,en;q=0.5")
        |> get("/letters/unsubscribe/" <> token)
        |> html_response(200)

      assert html =~ "Deixar de receber dicas e notícias sobre o produto em grace@app.test?"
    end

    test "the page is in the last letter's language, whatever the case of the address" do
      grace = person!(name: "Grace", email: "Grace.Hopper@App.Test", locale: "pt-PT")
      campaign = sequence!([step(0, "Olá")])
      {:ok, _} = Campaigns.enroll(campaign, "person:#{grace.id}")
      Tayori.Test.run_campaigns!()

      for address <- ["Grace.Hopper@App.Test", "grace.hopper@app.test"] do
        token = Letters.token(address, "product")
        html = build_conn() |> get("/letters/unsubscribe/" <> token) |> html_response(200)
        assert html =~ ~s(<html lang="pt-PT")
      end
    end

    test "the form unsubscribes from the purpose, or from everything", %{conn: conn} do
      token = Letters.token("ada@app.test", "marketing")

      html = conn |> form() |> post("/letters/unsubscribe/" <> token, %{}) |> html_response(200)
      assert html =~ "You&#39;re unsubscribed. These emails stop here."
      assert html =~ "Unsubscribe from everything"
      assert Campaigns.suppressed?("ada@app.test", "marketing")
      refute Campaigns.suppressed?("ada@app.test", "product")

      html =
        build_conn()
        |> form()
        |> post("/letters/unsubscribe/" <> token, %{"all" => "1"})
        |> html_response(200)

      assert html =~ "You&#39;re unsubscribed from everything."
      refute html =~ ~s(name="all")
      assert Campaigns.suppressed?("ada@app.test", "product")
    end

    test "one click from a mail client, with no CSRF token, gets an empty 200", %{conn: conn} do
      token = Letters.token("ada@app.test", "product")

      sent =
        conn |> form() |> post("/letters/unsubscribe/" <> token, "List-Unsubscribe=One-Click")

      assert response(sent, 200) == ""
      assert Campaigns.suppressed?("ada@app.test", "product")
      refute Campaigns.suppressed?("ada@app.test", "marketing")

      # A body that is not a form: the page's answer, and unsubscribed all the same.
      sent = build_conn() |> form() |> post("/letters/unsubscribe/" <> token, "%zz=%")
      assert html_response(sent, 200) =~ "You&#39;re unsubscribed."

      # Again: the same.
      sent =
        build_conn()
        |> post("/letters/unsubscribe/" <> token, %{"List-Unsubscribe" => "One-Click"})

      assert response(sent, 200) == ""
    end

    test "a link that is not one", %{conn: conn} do
      html = conn |> get("/letters/unsubscribe/nope") |> html_response(404)
      assert html =~ "This link does not work any more."

      assert build_conn()
             |> form()
             |> post("/letters/unsubscribe/nope", %{})
             |> html_response(404) =~
               "This link does not work any more."

      sent =
        build_conn() |> post("/letters/unsubscribe/nope", %{"List-Unsubscribe" => "One-Click"})

      assert response(sent, 404) == ""
    end

    test "a sequence's person who unsubscribed leaves it at their next time" do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome"), step(60, "Next")])
      {:ok, _} = Campaigns.enroll(campaign, "person:#{ada.id}", ~U[2026-03-02 09:00:00Z])
      Tayori.Test.run_campaigns!(~U[2026-03-02 09:00:00Z])

      [delivery] = Tayori.Config.get().repo.all(Delivery)
      assert delivery.status == "sent"

      token = Letters.token("ada@app.test", "product")
      build_conn() |> post("/letters/unsubscribe/" <> token, %{"List-Unsubscribe" => "One-Click"})

      Tayori.Test.run_campaigns!(~U[2026-03-04 09:00:00Z])

      assert [%{state: "exited", reason: "unsubscribed"}] =
               Tayori.Config.get().repo.all(Tayori.Campaigns.Enrollment)
    end
  end

  describe "webhooks" do
    setup do
      campaign = sequence!([step(0, "Welcome")])
      [step] = campaign.steps

      delivery =
        Tayori.Config.get().repo.insert!(%Delivery{
          campaign_id: campaign.id,
          step_id: step.id,
          person: "person:1",
          email: "ada@app.test",
          status: "sent",
          provider_id: "re_1"
        })

      %{delivery: delivery}
    end

    defp post_json(conn, path, body, headers) do
      conn
      |> put_req_header("content-type", "application/json")
      |> then(fn conn ->
        Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
      end)
      |> post(path, body)
    end

    defp status_of(delivery), do: Tayori.Config.get().repo.get!(Delivery, delivery.id).status

    test "Resend: a signed bounce suppresses the address", %{conn: conn, delivery: delivery} do
      body =
        JSON.encode!(%{
          "type" => "email.bounced",
          "data" => %{"email_id" => "re_1", "to" => ["ada@app.test"]}
        })

      sent = post_json(conn, "/letters/webhooks/resend", body, svix_headers(body))
      assert json_response(sent, 200) == %{"handled" => 1}
      assert status_of(delivery) == "bounced"
      assert Campaigns.suppressed?("ada@app.test", "product")
    end

    test "Resend: a bad or old signature is refused", %{conn: conn, delivery: delivery} do
      body =
        JSON.encode!(%{
          "type" => "email.complained",
          "data" => %{"email_id" => "re_1", "to" => ["ada@app.test"]}
        })

      bad = post_json(conn, "/letters/webhooks/resend", body <> " ", svix_headers(body))
      assert json_response(bad, 401) == %{"error" => "unauthorized"}

      old =
        post_json(
          build_conn(),
          "/letters/webhooks/resend",
          body,
          svix_headers(body, System.system_time(:second) - 600)
        )

      assert json_response(old, 401)

      none = post_json(build_conn(), "/letters/webhooks/resend", body, [])
      assert json_response(none, 401)

      assert status_of(delivery) == "sent"
      refute Campaigns.suppressed?("ada@app.test", "product")
    end

    test "Postmark: its basic authentication", %{conn: conn, delivery: delivery} do
      body =
        JSON.encode!(%{
          "RecordType" => "SpamComplaint",
          "Email" => "ada@app.test",
          "MessageID" => "re_1"
        })

      assert post_json(conn, "/letters/webhooks/postmark", body, [basic("tayori", "nope")])
             |> json_response(401)

      assert status_of(delivery) == "sent"

      sent =
        post_json(build_conn(), "/letters/webhooks/postmark", body, [basic("tayori", "s3cret")])

      assert json_response(sent, 200) == %{"handled" => 1}
      assert status_of(delivery) == "complained"
      assert Campaigns.suppressed?("ada@app.test", "marketing")
    end

    test "the app's own provider", %{conn: conn, delivery: delivery} do
      body =
        JSON.encode!(%{
          "events" => [
            %{"kind" => "delivered", "to" => "grace@app.test"},
            %{"kind" => "bounced", "to" => "ada@app.test", "id" => "re_1"},
            %{"kind" => "opened", "to" => "ada@app.test"}
          ]
        })

      assert post_json(conn, "/letters/webhooks/custom", body, [{"x-token", "nope"}])
             |> json_response(401)

      sent = post_json(build_conn(), "/letters/webhooks/custom", body, [{"x-token", "t0k"}])
      assert json_response(sent, 200) == %{"handled" => 2}
      assert status_of(delivery) == "bounced"
      refute Campaigns.suppressed?("grace@app.test", "product")
    end

    test "a provider not configured is a 404; a body not JSON a 400", %{conn: conn} do
      assert conn |> post_json("/letters/webhooks/ses", "{}", []) |> response(404)

      body = "not json"

      assert build_conn()
             |> post_json("/letters/webhooks/resend", body, svix_headers(body))
             |> json_response(400)
    end

    test "behind the endpoint's parsers, the raw body kept by Tayori.RawBody" do
      body =
        JSON.encode!(%{
          "type" => "email.bounced",
          "data" => %{"email_id" => "re_1", "to" => ["ada@app.test"]}
        })

      parse = fn conn, reader ->
        opts =
          Plug.Parsers.init(
            parsers: [:json],
            pass: ["*/*"],
            json_decoder: JSON,
            body_reader: reader
          )

        Plug.Parsers.call(conn, opts)
      end

      conn =
        Plug.Test.conn(:post, "/letters/webhooks/resend", body)
        |> put_req_header("content-type", "application/json")
        |> then(fn conn ->
          Enum.reduce(svix_headers(body), conn, fn {k, v}, c -> put_req_header(c, k, v) end)
        end)

      kept = parse.(conn, {Tayori.RawBody, :read_body, []})
      assert IO.iodata_to_binary(kept.private.tayori_raw_body) == body

      plain = parse.(conn, {Plug.Conn, :read_body, []})
      refute Map.has_key?(plain.private, :tayori_raw_body)

      # Another path keeps nothing.
      other =
        parse.(
          %{conn | path_info: ["letters", "unsubscribe", "x"]},
          {Tayori.RawBody, :read_body, []}
        )

      refute Map.has_key?(other.private, :tayori_raw_body)

      assert {:ok, ^body, _conn} = Tayori.RawBody.fetch(kept, 1_000)
      assert {:error, :no_raw_body} = Tayori.RawBody.fetch(plain, 1_000)

      # PhoenixMountable's reader, which asks the router.
      shared = parse.(conn, {PhoenixMountable.RawBody, :read_body, [TayoriTest.Host.Router]})
      assert {:ok, ^body, _conn} = Tayori.RawBody.fetch(shared, 1_000)
      assert {:error, :too_large} = Tayori.RawBody.fetch(shared, 10)

      other =
        parse.(
          %{conn | path_info: ["letters", "unsubscribe", "x"]},
          {PhoenixMountable.RawBody, :read_body, [TayoriTest.Host.Router]}
        )

      assert {:error, :no_raw_body} = Tayori.RawBody.fetch(other, 1_000)
    end
  end

  test "without the campaigns, every route is a 404", %{conn: conn, config: config} do
    put_config(config, modules: [:changelog], campaigns: nil)
    token = Letters.token("ada@app.test", "product")

    assert conn |> get("/letters/unsubscribe/" <> token) |> response(404)
    assert build_conn() |> post("/letters/unsubscribe/" <> token, %{}) |> response(404)

    assert build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("/letters/webhooks/resend", "{}")
           |> response(404)

    refute Campaigns.suppressed?("ada@app.test", "product")
  end
end
