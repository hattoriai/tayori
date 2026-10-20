if Code.ensure_loaded?(Swoosh.Email) do
  defmodule Tayori.Mail do
    @moduledoc false
    # The emails of the :subscriptions feature, as Swoosh emails for the
    # app's mailer: the confirmation of an address, an entry, and the
    # entries of a period (the :emails config). Each has
    # an HTML part, styled inline as email clients need, and a text part.

    import Swoosh.Email

    alias Tayori.{Config, Entry, Messages}

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

    defp button(href, label) do
      ~s(<a href="#{escape(href)}" style="display:inline-block;background:#1f1f23;color:#ffffff;text-decoration:none;padding:11px 18px;border-radius:6px;font-weight:500;font-size:15px">#{escape(label)}</a>)
    end

    defp layout(config, words, content, unsubscribe \\ nil) do
      name =
        case config.email_from do
          {name, _address} -> name
          _address -> words["title"]
        end

      footer =
        if unsubscribe,
          do:
            ~s(<a href="#{escape(unsubscribe)}" style="color:#6b6b76">#{escape(words["unsubscribe"])}</a>),
          else: ""

      """
      <!DOCTYPE html>
      <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
      <body style="margin:0;padding:0;background:#f6f6f7">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f6f6f7"><tr><td align="center" style="padding:32px 16px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;border:1px solid #e4e4e8;border-radius:12px">
      <tr><td style="padding:28px 32px 0;font:600 13px/1 system-ui,-apple-system,'Segoe UI',sans-serif;letter-spacing:.06em;text-transform:uppercase;color:#6b6b76">#{escape(name)}</td></tr>
      <tr><td style="padding:20px 32px 32px;font-family:system-ui,-apple-system,'Segoe UI',sans-serif;color:#1f1f23">#{content}</td></tr>
      </table>
      <p style="margin:20px 0 0;font:13px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:#6b6b76">#{footer}</p>
      </td></tr></table>
      </body></html>
      """
    end

    # Links and images of a body are relative to the app; an email needs
    # them whole.
    defp absolute(nil, _base), do: ""

    defp absolute(html, base) do
      origin = origin(base)
      Regex.replace(~r/(\s(?:src|href|poster))="\/(?!\/)/, html, "\\1=\"#{origin}/")
    end

    defp absolute_url("/" <> _ = path, base), do: origin(base) <> path
    defp absolute_url(url, _base), do: url

    defp origin(base) do
      uri = URI.parse(base)
      "#{uri.scheme}://#{uri.authority}"
    end

    defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end
end
