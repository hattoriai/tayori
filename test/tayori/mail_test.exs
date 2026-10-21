defmodule Tayori.MailTest do
  # The emails of the :subscriptions feature, byte for byte: their layout
  # is shared with the campaigns' letters (Tayori.Mail.Layout), and must
  # not change with it. TAYORI_PIN_MAIL=1 writes the files again.
  use ExUnit.Case, async: true

  alias Tayori.{Entry, Mail, Translation}

  @dir Path.expand("../support/fixtures/mail", __DIR__)

  defp config(from) do
    Tayori.Config.new(
      repo: TayoriTest.SQLiteRepo,
      pubsub: TayoriTest.PubSub,
      locales: ["en", "pt-PT"],
      features: [:subscriptions],
      mailer: TayoriTest.Mailer,
      email_from: from,
      page_url: "https://atelier.test/changelog"
    )
  end

  defp entry(slug, title, summary, markdown, cover \\ nil) do
    %Entry{
      slug: slug,
      cover: cover,
      translations: [
        %Translation{
          locale: "en",
          title: title,
          summary: summary,
          body: Kotoba.Content.from_markdown(markdown)
        }
      ]
    }
  end

  defp subscriber(locale), do: %{email: "ada@example.com", locale: locale, token: "tok-123"}

  defp emails do
    named = config({"Atelier", "news@atelier.test"})
    bare = config("news@atelier.test")

    exports =
      entry(
        "exports",
        "Exports <fast>",
        "One click & done.",
        "See [the docs](/docs/exports) and [elsewhere](https://elsewhere.test/x).\n\n![A chart](/uploads/chart.png)",
        %{"url" => "/uploads/cover.png", "alt" => "A <chart>"}
      )

    search = entry("search", "Search", nil, String.duplicate("Find anything, anywhere. ", 20))

    [
      {"confirm.html", Mail.confirm(named, subscriber("en"))},
      {"confirm-pt.html", Mail.confirm(bare, subscriber("pt-PT"))},
      {"entry.html", Mail.entry(named, exports, subscriber("en"))},
      {"entry-bare.html", Mail.entry(bare, search, subscriber("en"))},
      {"digest.html", Mail.digest(named, [exports, search], subscriber("en"))}
    ]
  end

  test "the emails are the same, byte for byte" do
    for {name, email} <- emails() do
      path = Path.join(@dir, name)
      text_path = Path.rootname(path) <> ".txt"

      if System.get_env("TAYORI_PIN_MAIL") == "1" do
        File.write!(path, email.html_body)
        File.write!(text_path, email.text_body)
      end

      assert email.html_body == File.read!(path), "#{name} changed"
      assert email.text_body == File.read!(text_path), "#{name} (text) changed"
    end
  end
end
