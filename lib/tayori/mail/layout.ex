defmodule Tayori.Mail.Layout do
  @moduledoc false
  # The look of Tayori's emails, shared by the changelog's (Tayori.Mail)
  # and the campaigns' letters (Tayori.Campaigns.Letters): a card on a
  # grey page, the sender's name above, a footer below, styled inline as
  # email clients need.

  @doc false
  # The whole document: the name at the top of the card, its content
  # (HTML), the footer (HTML, "" for none) and an optional preheader, the
  # line a mail client shows after the subject, hidden in the letter.
  @spec document(String.t(), iodata(), String.t(), String.t() | nil) :: String.t()
  def document(name, content, footer, preheader \\ nil) do
    """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
    <body style="margin:0;padding:0;background:#f6f6f7">
    #{preheader(preheader)}<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f6f6f7"><tr><td align="center" style="padding:32px 16px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;border:1px solid #e4e4e8;border-radius:12px">
    <tr><td style="padding:28px 32px 0;font:600 13px/1 system-ui,-apple-system,'Segoe UI',sans-serif;letter-spacing:.06em;text-transform:uppercase;color:#6b6b76">#{escape(name)}</td></tr>
    <tr><td style="padding:20px 32px 32px;font-family:system-ui,-apple-system,'Segoe UI',sans-serif;color:#1f1f23">#{content}</td></tr>
    </table>
    <p style="margin:20px 0 0;font:13px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:#6b6b76">#{footer}</p>
    </td></tr></table>
    </body></html>
    """
  end

  defp preheader(nil), do: ""

  defp preheader(text) do
    ~s(<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all">#{escape(text)}</div>\n)
  end

  @doc false
  # The link of the footer: to unsubscribe.
  @spec footer_link(String.t(), String.t()) :: String.t()
  def footer_link(href, label) do
    ~s(<a href="#{escape(href)}" style="color:#6b6b76">#{escape(label)}</a>)
  end

  @doc false
  @spec button(String.t(), String.t()) :: String.t()
  def button(href, label) do
    ~s(<a href="#{escape(href)}" style="display:inline-block;background:#1f1f23;color:#ffffff;text-decoration:none;padding:11px 18px;border-radius:6px;font-weight:500;font-size:15px">#{escape(label)}</a>)
  end

  @doc false
  # Links and images of a body are relative to the app; an email needs
  # them whole.
  @spec absolute(String.t() | nil, String.t()) :: String.t()
  def absolute(nil, _base), do: ""

  def absolute(html, base) do
    origin = origin(base)
    Regex.replace(~r/(\s(?:src|href|poster))="\/(?!\/)/, html, "\\1=\"#{origin}/")
  end

  @doc false
  @spec absolute_url(String.t(), String.t()) :: String.t()
  def absolute_url("/" <> _ = path, base), do: origin(base) <> path
  def absolute_url(url, _base), do: url

  defp origin(base) do
    uri = URI.parse(base)
    "#{uri.scheme}://#{uri.authority}"
  end

  @doc false
  @spec escape(term()) :: String.t()
  def escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
