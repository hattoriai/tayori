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

  test "the scheduler runs unless the app says not to" do
    assert Config.new(@base).scheduler
    refute Config.new(@base ++ [scheduler: false]).scheduler

    assert_raise ArgumentError, ~r/:scheduler must be true or false/, fn ->
      Config.new(@base ++ [scheduler: :no])
    end
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

    # A family and a flag are one emoji, longer than most in bytes.
    assert Config.new(@base ++ [reactions: ["👨‍👩‍👧", "🇵🇹"]]).reactions == ["👨‍👩‍👧", "🇵🇹"]

    for bad <- [[], ["ok"], ["👍", "a"], ["1"], [" "], [""], [:thumbs], "👍", ["👍👍"]] do
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

    assert_raise ArgumentError, ~r/:locales/, fn ->
      Config.new(@base ++ [locales: [{"en", ""}]])
    end

    # The app names its languages; Tayori names none.
    config =
      Config.new(@base ++ [locales: [{"en", "English"}, "zh-Hant", {"pt-PT", "Português"}]])

    assert config.locales == ["en", "zh-Hant", "pt-PT"]
    assert config.locale_names == %{"en" => "English", "pt-PT" => "Português"}
    assert Tayori.Locales.name(config, "pt-PT") == "Português"
    assert Tayori.Locales.name(config, "zh-Hant") == "zh-Hant"

    assert_raise ArgumentError, ~r/:secret_key_base/, fn ->
      Config.new(@base ++ [secret_key_base: "short"])
    end
  end

  describe "modules" do
    @campaigns [
      modules: [:changelog, :campaigns],
      mailer: TayoriTest.Mailer,
      secret_key_base: String.duplicate("tayori-test-secret-", 4),
      campaigns: [audience: TayoriTest.Audience, url: "https://app.test/letters/"],
      email_from: {"Atelier", "news@atelier.test"}
    ]

    test "the changelog alone by default, as before" do
      config = Config.new(@base)
      assert config.modules == [:changelog]
      assert Config.module?(config, :changelog)
      refute Config.module?(config, :campaigns)
      assert config.campaigns == nil
      assert Config.modules() == [:changelog, :campaigns]
    end

    test "the modules given, once each; an unknown one or none is refused" do
      config = Config.new(@base ++ Keyword.put(@campaigns, :modules, [:campaigns, :campaigns]))
      assert config.modules == [:campaigns]
      refute Config.module?(config, :changelog)

      for bad <- [[], [:polls], :changelog, [:changelog, :polls]] do
        assert_raise ArgumentError, ~r/:modules must be a list of/, fn ->
          Config.new(@base ++ [modules: bad])
        end
      end
    end

    test "the features are the changelog's" do
      assert_raise ArgumentError, ~r/:features are the changelog's/, fn ->
        Config.new(
          @base ++ Keyword.merge(@campaigns, modules: [:campaigns], features: [:reactions])
        )
      end

      assert Config.new(@base ++ Keyword.put(@campaigns, :features, [:reactions])).features ==
               [:reactions]
    end

    test "the campaigns' option, checked" do
      config = Config.new(@base ++ @campaigns)

      assert config.campaigns == %{
               audience: TayoriTest.Audience,
               url: "https://app.test/letters",
               from: {"Atelier", "news@atelier.test"},
               reply_to: nil,
               providers: %{},
               keep_events_days: 400
             }

      config =
        Config.new(
          @base ++
            Keyword.put(@campaigns, :campaigns,
              audience: TayoriTest.Audience,
              url: "https://app.test/letters",
              from: "rui@app.test",
              reply_to: "help@app.test",
              keep_events_days: 30,
              providers: [
                resend: [secret: "whsec_abc"],
                postmark: [username: "u", password: "p"],
                custom: {TayoriTest.Provider, topic: "t"}
              ]
            )
        )

      assert %{from: "rui@app.test", reply_to: "help@app.test", keep_events_days: 30} =
               config.campaigns

      assert config.campaigns.providers == %{
               resend: {Tayori.Campaigns.Providers.Resend, %{secret: "whsec_abc"}},
               postmark: {Tayori.Campaigns.Providers.Postmark, %{username: "u", password: "p"}},
               custom: {TayoriTest.Provider, %{topic: "t"}}
             }

      # Without the module, the option is not read.
      assert Config.new(@base ++ [campaigns: :nonsense]).campaigns == nil
    end

    test "the campaigns need a mailer, a secret, an audience, an address and a sender" do
      for key <- [:mailer, :secret_key_base] do
        assert_raise ArgumentError,
                     "the :campaigns module needs the #{inspect(key)} option",
                     fn ->
                       Config.new(@base ++ Keyword.delete(@campaigns, key))
                     end
      end

      assert_raise ArgumentError, ~r/needs the :campaigns option/, fn ->
        Config.new(@base ++ Keyword.delete(@campaigns, :campaigns))
      end

      assert_raise ArgumentError, ~r/needs who the letters are from/, fn ->
        Config.new(@base ++ Keyword.delete(@campaigns, :email_from))
      end

      bad = [
        {[url: "https://app.test/letters"], ~r/needs :audience/},
        {[audience: Kernel, url: "https://app.test/letters"], ~r/must be a Tayori.Audience/},
        {[audience: TayoriTest.Audience], ~r/needs :url/},
        {[audience: TayoriTest.Audience, url: "/letters"], ~r/http\(s\) address/},
        {[audience: TayoriTest.Audience, url: "https://app.test", from: "nobody"],
         ~r/:from of :campaigns must be an address/},
        {[audience: TayoriTest.Audience, url: "https://app.test", reply_to: "nobody"],
         ~r/:reply_to/},
        {[audience: TayoriTest.Audience, url: "https://app.test", keep_events_days: 0],
         ~r/:keep_events_days/},
        {[audience: TayoriTest.Audience, url: "https://app.test", providers: [resend: []]],
         ~r/whsec_/},
        {[audience: TayoriTest.Audience, url: "https://app.test", providers: [postmark: []]],
         ~r/username/},
        {[audience: TayoriTest.Audience, url: "https://app.test", providers: [ses: {Kernel, []}]],
         ~r/is not a Tayori.Campaigns.Provider/},
        {[audience: TayoriTest.Audience, url: "https://app.test", providers: [ses: :nope]],
         ~r/:providers of :campaigns takes/},
        {[audience: TayoriTest.Audience, url: "https://app.test", sender: "x"],
         ~r/:campaigns takes/},
        {:nonsense, ~r/must be a keyword list/}
      ]

      for {campaigns, message} <- bad do
        assert_raise ArgumentError, message, fn ->
          Config.new(@base ++ Keyword.put(@campaigns, :campaigns, campaigns))
        end
      end
    end

    test "option/2 checks the modules and the campaigns, for the tests" do
      assert Config.option(:modules, [:campaigns]) == [:campaigns]
      assert_raise ArgumentError, fn -> Config.option(:modules, []) end

      assert %{audience: TayoriTest.Audience, from: "a@app.test"} =
               Config.option(:campaigns,
                 audience: TayoriTest.Audience,
                 url: "https://app.test",
                 from: "a@app.test"
               )

      assert Config.option(:campaigns, nil) == nil
    end
  end
end
