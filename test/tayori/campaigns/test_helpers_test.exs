defmodule Tayori.Campaigns.TestHelpersTest do
  # Tayori.Test's helpers of the campaigns, as an app's tests use them.
  use TayoriTest.DataCase

  import Swoosh.TestAssertions
  import Tayori.Test

  alias Tayori.Campaigns

  @t0 ~U[2026-03-02 09:00:00.000000Z]

  defp oban_of(TayoriTest.SQLiteRepo), do: TayoriTest.SQLiteOban
  defp oban_of(TayoriTest.PostgresRepo), do: TayoriTest.PostgresOban

  for_each_repo do
    setup :campaigns

    test "track!/3 and run_campaigns!/2: the letters at their times, in the test's process" do
      ada = person!(name: "Ada")

      sequence!(%{"trigger" => %{"type" => "event", "event" => "signed_up"}}, [
        step(0, "Welcome"),
        step(2 * 1440, "Day two")
      ])

      assert :ok = track!(person_id(ada), "signed_up", at: @t0)
      assert :ok = run_campaigns!(@t0)
      assert_email_sent(subject: "Welcome")

      run_campaigns!(later(@t0, 1))
      refute_email_sent()
      run_campaigns!(later(@t0, 2))
      assert_email_sent(subject: "Day two")
    end

    test "with Oban too, the letters go at once", %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo))
      for name <- ["Ada", "Grace", "Alan"], do: person!(name: name)
      {:ok, _} = Campaigns.schedule_broadcast(broadcast!("Spring"), @t0)

      run_campaigns!(@t0, batch_size: 2)
      for _ <- 1..3, do: assert_email_sent(subject: "Spring")
    end

    test "post_webhook!/2: a provider's payload, its signature aside", %{config: config} do
      put_config(config,
        campaigns: [
          audience: TayoriTest.Audience,
          url: "https://app.test/letters",
          from: "rui@app.test",
          providers: [resend: [secret: "whsec_c2VjcmV0"]]
        ]
      )

      assert 1 =
               post_webhook!(:resend, %{
                 "type" => "email.bounced",
                 "data" => %{"email_id" => "re_1", "to" => ["ada@app.test"]}
               })

      assert Campaigns.suppressed?("ada@app.test", :product)

      assert_raise ArgumentError, ~r/not in the :providers/, fn ->
        post_webhook!(:postmark, %{})
      end
    end
  end

  test "without the campaigns, the helpers say so" do
    {:ok, _} = TayoriTest.DataCase.checkout(TayoriTest.SQLiteRepo)

    assert_raise ArgumentError, ~r/campaigns module is off/, fn -> track!("person:1", "x") end
    assert_raise ArgumentError, ~r/campaigns module is off/, fn -> run_campaigns!() end
  end
end
