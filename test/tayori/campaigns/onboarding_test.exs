defmodule Tayori.Campaigns.OnboardingTest do
  # indie.camera's letters of a site's first days (IndieCamera.Onboarding),
  # as a Tayori sequence over the fake app: a person is a site with its
  # owner, a photo a photograph, a story a story. The same letters go at
  # the same times:
  #
  #   * welcome, at sign-up
  #   * photographs, from day 2: no photograph and no story yet
  #   * story, from day 4: no story yet
  #   * layouts, from day 6: a story, not published
  #   * publish, from day 9
  #
  # once each, one at most every 40 hours, within the first 14 days, and
  # none once a story is published, the site is closed, or its owner
  # turned the optional emails off.
  use TayoriTest.DataCase

  import Swoosh.TestAssertions
  import Tayori.Test

  alias Tayori.Campaigns

  @t0 ~U[2026-03-02 09:00:00.000000Z]
  @day 1440

  # The sequence, as the admin or a seed would make it.
  defp onboarding! do
    has = &%{"attribute" => &1, "op" => "true"}

    sequence!(
      %{
        "name" => "Onboarding",
        # The optional emails: the owner's consent (can_email?/2).
        "purpose" => "marketing",
        "trigger" => %{"type" => "event", "event" => "signed_up"},
        "goal" => has.("published"),
        "min_gap_hours" => 40,
        "max_days" => 14
      },
      [
        step(0, "Welcome to indie.camera"),
        step(2 * @day, "Start with one series",
          skip_if: %{"any" => [has.("has_photos"), has.("has_story")]}
        ),
        step(4 * @day, "A cover and a title", skip_if: has.("has_story")),
        step(6 * @day, "Try another layout", skip_if: %{"not" => has.("has_story")}),
        step(9 * @day, "Publish your first story")
      ]
    )
  end

  defp sign_up!(attrs \\ %{}) do
    site = person!(Map.merge(%{name: "Harbour Studio", email: "owner@harbour.test"}, attrs))
    track!(person_id(site), "signed_up", at: @t0)
    site
  end

  defp at(days, hours \\ 0), do: @t0 |> DateTime.add(days, :day) |> DateTime.add(hours, :hour)

  # The letters a run at a time sends, by subject.
  defp letters_at(time) do
    run_campaigns!(time)
    sent()
  end

  defp sent do
    receive do
      {:email, email} -> [email.subject | sent()]
    after
      0 -> []
    end
  end

  for_each_repo do
    setup :campaigns

    setup do
      %{campaign: onboarding!()}
    end

    test "nothing done: welcome, photographs, story, publish; no layouts", %{campaign: campaign} do
      site = sign_up!()

      assert letters_at(at(0)) == ["Welcome to indie.camera"]
      assert letters_at(at(1)) == []
      assert letters_at(at(2)) == ["Start with one series"]
      assert letters_at(at(3)) == []
      assert letters_at(at(4)) == ["A cover and a title"]
      # Layouts are for a story: left out.
      assert letters_at(at(6)) == []
      assert letters_at(at(8)) == []
      assert letters_at(at(9)) == ["Publish your first story"]
      assert letters_at(at(13)) == []

      assert %{state: "completed", reason: "finished"} = enrollment(campaign, site)
      assert Enum.count(deliveries(campaign), &(&1.status == "sent")) == 4

      assert [{"skipped", "skip_if"}] =
               for(d <- deliveries(campaign), d.status == "skipped", do: {d.status, d.reason})
    end

    test "photographs but no story: the cover letter, not the series" do
      site = sign_up!()
      assert letters_at(at(0)) == ["Welcome to indie.camera"]
      photo!(site)

      assert letters_at(at(2)) == []
      assert letters_at(at(4)) == ["A cover and a title"]
    end

    test "a step already taken is passed over: a story, so neither the series nor the cover" do
      site = sign_up!()
      assert letters_at(at(0)) == ["Welcome to indie.camera"]
      story!(site)

      assert letters_at(at(5)) == []
      assert letters_at(at(6)) == ["Try another layout"]
      assert letters_at(at(9)) == ["Publish your first story"]
    end

    test "one letter at most every 40 hours" do
      # Ten days in before anything runs: every step is due, but they go
      # one at a time.
      sign_up!()

      assert letters_at(at(10)) == ["Welcome to indie.camera"]
      assert letters_at(at(10, 39)) == []
      assert letters_at(at(10, 41)) == ["Start with one series"]
      assert letters_at(at(10, 80)) == []
      assert letters_at(at(10, 81)) == ["A cover and a title"]
    end

    test "nothing after the first 14 days", %{campaign: campaign} do
      late = sign_up!()
      assert letters_at(at(15)) == []
      assert %{state: "completed", reason: "expired"} = enrollment(campaign, late)
    end

    test "within the 14 days, a letter still goes" do
      sign_up!()
      assert letters_at(at(0)) == ["Welcome to indie.camera"]
      assert letters_at(at(13)) == ["Start with one series"]
    end

    test "nothing once a story is published", %{campaign: campaign} do
      site = sign_up!()
      assert letters_at(at(0)) == ["Welcome to indie.camera"]
      story!(site, at(3))

      assert letters_at(at(9)) == []
      assert %{state: "completed", reason: "goal"} = enrollment(campaign, site)

      assert %{goal: 1, steps: [%{goal_after: 1} | _]} = Campaigns.results(campaign)
    end

    test "nothing to a closed site", %{campaign: campaign, repo: repo} do
      site = sign_up!()
      assert letters_at(at(0)) == ["Welcome to indie.camera"]
      repo.update!(Ecto.Changeset.change(site, closed_at: at(1)))

      assert letters_at(at(2)) == []
      assert %{state: "exited", reason: "left"} = enrollment(campaign, site)
    end

    test "nothing to an owner who stopped the optional emails", %{campaign: campaign} do
      site = sign_up!(%{optional_emails: false})

      assert letters_at(at(0)) == []
      assert_no_email_sent()
      assert %{state: "exited", reason: "cannot_email"} = enrollment(campaign, site)
    end

    test "each letter once: signing up again, or running twice", %{campaign: campaign} do
      site = sign_up!()
      track!(person_id(site), "signed_up", at: at(1))

      assert letters_at(at(0)) == ["Welcome to indie.camera"]
      assert letters_at(at(0)) == []
      assert letters_at(at(2)) == ["Start with one series"]
      assert letters_at(at(2)) == []
      assert Campaigns.results(campaign).entered == 1
    end
  end
end
