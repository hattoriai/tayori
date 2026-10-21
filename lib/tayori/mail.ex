if Code.ensure_loaded?(Swoosh.Email) do
  defmodule Tayori.Mail do
    @moduledoc false
    # The emails of the :subscriptions feature, as Swoosh emails for the
    # app's mailer: the confirmation of an address, an entry, and the
    # entries of a period (the :emails config). Each has
    # an HTML part, styled inline as email clients need, and a text part.

    import Swoosh.Email

    import Tayori.Mail.Layout, only: [absolute: 2, absolute_url: 2, button: 2, escape: 1]

    alias Tayori.{Config, Entry, Messages}
    alias Tayori.Mail.Layout

    @doc false
    def confirm(%Config{} = config, subscriber) do
      words = Messages.for_locale(subscriber.locale)
      link = config.page_url <> "/subscription/confirm/" <> subscriber.token

      new()
      |> to(subscriber.email)
      |> from(config.email_from)
      |> subject(words["confirmSubject"])
      |> text_body("""
      #{words["confirmText"]}

      #{link}

      #{words["confirmIgnore"]}
      """)
      |> html_body(
        layout(config, words, """
        <p style="margin:0 0 24px">#{escape(words["confirmText"])}</p>
        #{button(link, words["confirmButton"])}
        <p style="margin:24px 0 0;color:#6b6b76;font-size:14px">#{escape(words["confirmIgnore"])}</p>
        """)
      )
    end

    @doc false
    def entry(%Config{} = config, %Entry{} = entry, subscriber) do
      words = Messages.for_locale(subscriber.locale)
      translation = Entry.translation(entry, subscriber.locale, config.locales)
      link = config.page_url <> "/" <> entry.slug <> "?ref=email"
      unsubscribe = config.page_url <> "/subscription/unsubscribe/" <> subscriber.token
      body = absolute(translation.body && translation.body.html, config.page_url)

      new()
      |> to(subscriber.email)
      |> from(config.email_from)
      |> subject(translation.title)
      |> header("List-Unsubscribe", "<" <> unsubscribe <> ">")
      |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
      |> text_body("""
      #{translation.title}

      #{translation.summary || ""}

      #{(translation.body && translation.body.text) || ""}

      #{words["readOnline"]}: #{link}

      #{words["unsubscribe"]}: #{unsubscribe}
      """)
      |> html_body(
        layout(
          config,
          words,
          """
          #{cover(entry.cover, config.page_url)}
          <h1 style="margin:0 0 12px;font-size:26px;line-height:1.25;font-weight:600;color:#1f1f23">#{escape(translation.title)}</h1>
          #{if translation.summary, do: ~s(<p style="margin:0 0 20px;font-size:17px;color:#45454d">#{escape(translation.summary)}</p>), else: ""}
          <div style="font-size:16px;line-height:1.65;color:#1f1f23">#{body}</div>
          <div style="margin-top:28px">#{button(link, words["readOnline"])}</div>
          """,
          unsubscribe
        )
      )
    end

    @doc false
    # The entries of a period, in one email: each one's title, summary
    # and link, the newest first.
    def digest(%Config{} = config, entries, subscriber) do
      words = Messages.for_locale(subscriber.locale)
      unsubscribe = config.page_url <> "/subscription/unsubscribe/" <> subscriber.token
      all = config.page_url <> "?ref=email"

      items =
        Enum.map(entries, fn entry ->
          translation = Entry.translation(entry, subscriber.locale, config.locales)

          %{
            title: translation.title,
            summary: translation.summary || excerpt(translation.body && translation.body.text),
            link: config.page_url <> "/" <> entry.slug <> "?ref=email"
          }
        end)

      new()
      |> to(subscriber.email)
      |> from(config.email_from)
      |> subject(digest_subject(words, items))
      |> header("List-Unsubscribe", "<" <> unsubscribe <> ">")
      |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
      |> text_body("""
      #{words["title"]}

      #{Enum.map_join(items, "\n\n", &text_item(&1, words))}

      #{words["allNews"]}: #{all}

      #{words["unsubscribe"]}: #{unsubscribe}
      """)
      |> html_body(
        layout(
          config,
          words,
          """
          <h1 style="margin:0 0 20px;font-size:26px;line-height:1.25;font-weight:600;color:#1f1f23">#{escape(words["title"])}</h1>
          #{Enum.map_join(items, "\n", &html_item(&1, words))}
          <div style="margin-top:28px">#{button(all, words["allNews"])}</div>
          """,
          unsubscribe
        )
      )
    end

    # The titles, as many as a subject shows.
    defp digest_subject(words, items) do
      subject = words["title"] <> ": " <> Enum.map_join(items, ", ", & &1.title)
      if String.length(subject) > 110, do: String.slice(subject, 0, 109) <> "…", else: subject
    end

    defp text_item(item, words) do
      [item.title, item.summary, "#{words["readMore"]}: #{item.link}"]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")
    end

    defp html_item(item, words) do
      summary =
        if item.summary in [nil, ""],
          do: "",
          else:
            ~s(<p style="margin:0 0 8px;font-size:16px;line-height:1.6;color:#45454d">#{escape(item.summary)}</p>)

      """
      <div style="padding:20px 0;border-top:1px solid #e4e4e8">
      <h2 style="margin:0 0 8px;font-size:19px;line-height:1.3;font-weight:600"><a href="#{escape(item.link)}" style="color:#1f1f23;text-decoration:none">#{escape(item.title)}</a></h2>
      #{summary}
      <a href="#{escape(item.link)}" style="font-size:15px;color:#1f1f23">#{escape(words["readMore"])}</a>
      </div>
      """
    end

    # The first words of a body without a summary.
    defp excerpt(nil), do: nil

    defp excerpt(text) do
      text = text |> String.replace(~r/\s+/u, " ") |> String.trim()
      if String.length(text) > 200, do: String.slice(text, 0, 199) <> "…", else: text
    end

    defp cover(%{"url" => url} = cover, base) do
      ~s(<img src="#{escape(absolute_url(url, base))}" alt="#{escape(cover["alt"] || "")}" width="560" style="display:block;width:100%;max-width:560px;height:auto;border-radius:8px;margin:0 0 24px" />)
    end

    defp cover(_cover, _base), do: ""

    defp layout(config, words, content, unsubscribe \\ nil) do
      name =
        case config.email_from do
          {name, _address} -> name
          _address -> words["title"]
        end

      footer = if unsubscribe, do: Layout.footer_link(unsubscribe, words["unsubscribe"]), else: ""
      Layout.document(name, content, footer)
    end
  end
end
