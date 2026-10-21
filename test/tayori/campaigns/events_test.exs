defmodule Tayori.Campaigns.EventsTest do
  use TayoriTest.DataCase

  alias Tayori.Campaigns.{Event, Events}

  defp events(repo), do: repo.all(Event)

  for_each_repo do
    test "without the campaigns, track/3 keeps nothing", %{repo: repo} do
      assert Tayori.track("person:1", "signed_up") == :ok
      assert events(repo) == []
    end

    test "track/3 keeps the event, with its meta and its time", %{config: config, repo: repo} do
      put_config(config, TayoriTest.DataCase.campaigns_config())
      at = ~U[2026-10-01 09:00:00Z]

      assert Tayori.track("person:1", "signed_up") == :ok
      assert Tayori.track("person:1", "story_published", meta: %{"story" => 7}, at: at) == :ok

      assert [first, second] = Enum.sort_by(events(repo), & &1.name)
      assert %Event{person: "person:1", name: "signed_up", meta: nil} = first
      assert DateTime.diff(DateTime.utc_now(), first.occurred_at) < 5
      assert %Event{name: "story_published", meta: %{"story" => 7}} = second
      assert DateTime.compare(second.occurred_at, at) == :eq

      assert_raise ArgumentError, ~r/Tayori.track\/3 takes/, fn ->
        Tayori.track("person:1", String.duplicate("a", 65))
      end

      assert_raise ArgumentError, ~r/Tayori.track\/3 takes/, fn -> Tayori.track("", "x") end
    end

    test "the events older than the days kept are deleted", %{config: config, repo: repo} do
      opts = TayoriTest.DataCase.campaigns_config()
      config = put_config(config, put_in(opts, [:campaigns, :keep_events_days], 30))
      now = ~U[2026-10-21 12:00:00Z]

      Tayori.track("person:1", "old", at: DateTime.add(now, -31, :day))
      Tayori.track("person:1", "recent", at: DateTime.add(now, -29, :day))

      assert Events.delete_old(config, now) == 1
      assert [%Event{name: "recent"}] = events(repo)
      assert Events.delete_old(config, now) == 0

      # Without the campaigns, nothing to do.
      assert Events.delete_old(%{config | campaigns: nil}, now) == 0
    end
  end
end
