defmodule Tayori.ConfigTest do
  use ExUnit.Case, async: true

  alias Tayori.Config

  @base [repo: TayoriTest.SQLiteRepo, pubsub: TayoriTest.PubSub]

  test "the repo and the PubSub are needed" do
    assert_raise ArgumentError, ~r/:repo/, fn -> Config.new(pubsub: TayoriTest.PubSub) end
    assert_raise ArgumentError, ~r/:pubsub/, fn -> Config.new(repo: TayoriTest.SQLiteRepo) end
  end

  test "no feature by default; the features given, once each" do
    assert Config.new(@base).features == []

    config = Config.new(@base ++ [features: [:reactions, :analytics, :reactions]])
    assert config.features == [:reactions, :analytics]
    assert Config.feature?(config, :reactions)
    refute Config.feature?(config, :webhooks)

    assert Config.features() == [
             :reactions,
             :announcements,
             :analytics,
             :subscriptions,
             :webhooks,
             :embed
           ]
  end

  test "an unknown feature is refused" do
    assert_raise ArgumentError, ~r/:features must be a list of/, fn ->
      Config.new(@base ++ [features: [:reactions, :polls]])
    end

    assert_raise ArgumentError, ~r/:features must be a list of/, fn ->
      Config.new(@base ++ [features: :reactions])
    end
  end

  test "the reactions: the default emoji, or the app's, each an emoji" do
    assert Config.new(@base).reactions == ["👍", "🎉", "❤️", "🚀", "👀"]
    assert Config.new(@base ++ [reactions: ["💯", "🙏🏽", "🏳️‍🌈"]]).reactions == ["💯", "🙏🏽", "🏳️‍🌈"]

    for bad <- [[], ["ok"], ["👍", "a"], ["1"], [" "], [""], [:thumbs], "👍"] do
      assert_raise ArgumentError, ~r/:reactions must be a list of emoji/, fn ->
        Config.new(@base ++ [reactions: bad])
      end
    end
  end

  test ":subscriptions needs the mailer, who the emails are from and the page's address" do
    opts = [
      features: [:subscriptions],
      mailer: TayoriTest.Mailer,
      email_from: {"Atelier", "news@atelier.test"},
      page_url: "https://atelier.test/changelog/"
    ]

    config = Config.new(@base ++ opts)
    assert config.mailer == TayoriTest.Mailer
    assert config.page_url == "https://atelier.test/changelog"

    for key <- [:mailer, :email_from, :page_url] do
      assert_raise ArgumentError,
                   "the :subscriptions feature needs the #{inspect(key)} option",
                   fn ->
                     Config.new(@base ++ Keyword.delete(opts, key))
                   end
    end

    # Without the feature, they are not needed.
    assert Config.new(@base ++ [features: [:reactions]]).mailer == nil
  end

  test "the locales and the secret are checked" do
    assert Config.default_locale(Config.new(@base)) == "en"
    assert Config.default_locale(Config.new(@base ++ [locales: ["pt-PT", "en"]])) == "pt-PT"
    assert_raise ArgumentError, ~r/:locales/, fn -> Config.new(@base ++ [locales: []]) end

    assert_raise ArgumentError, ~r/:secret_key_base/, fn ->
      Config.new(@base ++ [secret_key_base: "short"])
    end
  end
end
