if Code.ensure_loaded?(Swoosh.Email) do
  defmodule Tayori.Campaigns.Letters do
    @moduledoc ~S"""
    A step's letter, as an email to one person: in their language, with
    their merge tags, a link to unsubscribe, in the look of Tayori's
    emails.

    The letter is the step's in the person's locale, else one of their
    language, else the app's first language, else the first there is.

    ## Merge tags

    A letter may name what it knows of the person: `{{name}}`,
    `{{email}}`, and any key of their recipient's `:data`
    (`{{first_name}}`, `{{dashboard_url}}`), with a fallback for a person
    who has none: `{{first_name|there}}`. A tag with no value and no
    fallback is left empty. Tags are replaced in the subject, the
    preheader, the body, its links and the button. In the HTML, the
    values are escaped; in a link, a value at its start must be an
    address (`https:`, `http:` or `mailto:`), and a value after it is
    encoded as a part of the address.

    ## Unsubscribing

    Each letter has a link to unsubscribe from its purpose (`"product"`
    or `"marketing"`), in its footer and in the `List-Unsubscribe`
    headers, with one-click unsubscribing (RFC 8058). The link is
    `{campaigns url}/unsubscribe/{token}`, the token signed with the
    `:secret_key_base`; it does not expire.
    """

    import Swoosh.Email

    alias Tayori.{Audience, Config, Messages, Recipient}
    alias Tayori.Campaigns.{Campaign, Letter, Step}
    alias Tayori.Mail.Layout

    @salt "tayori unsubscribe"
    @tag ~r/\{\{\s*([A-Za-z0-9_]+)\s*(?:\|([^{}]*))?\}\}/
    @leading_tag ~r/\A\{\{\s*([A-Za-z0-9_]+)\s*(?:\|([^{}]*))?\}\}/

    @doc """
    The letter of a step for a locale: the locale's, else one of its
    language, else the app's first language's, else the first. Nil for a
    step with none. The step's letters must be loaded.
    """
    @spec letter(Step.t(), String.t() | nil) :: Letter.t() | nil
    def letter(%Step{letters: letters}, locale) do
      config = Config.get()
      language = locale && language(locale)

      Enum.find(letters, &(&1.locale == locale)) ||
        (language && Enum.find(letters, &(language(&1.locale) == language))) ||
        Enum.find(letters, &(&1.locale == Config.default_locale(config))) ||
        List.first(letters)
    end

    defp language(locale), do: locale |> String.split(["-", "_"]) |> hd() |> String.downcase()

    @doc """
    A step's letter to a person, as a Swoosh email for the app's mailer.
    The step's letters must be loaded.

    Options: `:to` - another address to send it to, which its link to
    unsubscribe is for too (a test); `:test` - the subject begins with
    "[Test] ".
    """
    @spec render(Campaign.t(), Step.t(), Recipient.t(), keyword()) :: Swoosh.Email.t()
    def render(%Campaign{} = campaign, %Step{} = step, %Recipient{} = recipient, opts \\ []) do
      campaigns = Config.get().campaigns

      letter =
        letter(step, recipient.locale) ||
          raise ArgumentError, "the step #{step.id} has no letter"

      address = opts[:to] || recipient.email
      words = Messages.for_locale(letter.locale)
      unsubscribe = unsubscribe_url(address, campaign.purpose)
      values = values(recipient)
      button = button(letter, values)

      new()
      |> to({recipient.name || "", address})
      |> from(sender(campaign, campaigns))
      |> reply_to_of(campaign.reply_to || campaigns.reply_to)
      |> subject(subject(letter, values, opts[:test]))
      |> header("List-Unsubscribe", "<" <> unsubscribe <> ">")
      |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
      |> html_body(html(campaign, campaigns, letter, values, button, words, unsubscribe))
      |> text_body(text(letter, values, button, words, unsubscribe))
    end

    defp reply_to_of(email, nil), do: email
    defp reply_to_of(email, address), do: reply_to(email, address)

    defp subject(letter, values, true), do: "[Test] " <> merge(letter.subject, values)
    defp subject(letter, values, _test), do: merge(letter.subject, values)

    defp html(campaign, campaigns, letter, values, button, words, unsubscribe) do
      body =
        (letter.body && letter.body.html)
        |> Layout.absolute(campaigns.url)
        |> merge_html(values)

      button =
        if button,
          do: ~s(<div style="margin-top:28px">#{Layout.button(button.url, button.label)}</div>),
          else: ""

      Layout.document(
        masthead(campaign, campaigns),
        """
        <div style="font-size:16px;line-height:1.65;color:#1f1f23">#{body}</div>
        #{button}
        """,
        Layout.footer_link(unsubscribe, words["unsubscribe"]),
        letter.preheader && merge(letter.preheader, values)
      )
    end

    defp text(letter, values, button, words, unsubscribe) do
      [
        merge(letter.text || "", values),
        button && "#{button.label}: #{button.url}",
        "#{words["unsubscribe"]}: #{unsubscribe}"
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")
      |> Kernel.<>("\n")
    end

    @doc """
    Sends a step's letter as a test to an address: the subject begins
    with "[Test] ", the merge tags are those of a person (a recipient, the
    id of one, or nil for none), and no delivery is kept.
    """
    @spec send_test(Campaign.t(), Step.t(), Recipient.t() | String.t() | nil, String.t()) ::
            {:ok, term()} | {:error, term()}
    def send_test(%Campaign{} = campaign, %Step{} = step, person, address)
        when is_binary(address) do
      config = Config.get()
      step = config.repo.preload(step, :letters, prefix: config.prefix)

      recipient =
        case person do
          %Recipient{} = recipient -> recipient
          id when is_binary(id) -> Audience.get(id) || %Recipient{id: id, email: address}
          nil -> %Recipient{id: "test", email: address}
        end

      campaign
      |> render(step, recipient, to: address, test: true)
      |> config.mailer.deliver()
    end

    # The button, when it has a label and its address is one, tags merged.
    defp button(%Letter{cta_label: label, cta_url: url}, values)
         when is_binary(label) and is_binary(url) do
      url = merge_url(url, values, & &1)

      if http?(url), do: %{label: merge(label, values), url: url}
    end

    defp button(_letter, _values), do: nil

    defp masthead(campaign, campaigns) do
      case {campaign.from_name, campaigns.from} do
        {name, _from} when is_binary(name) -> name
        {nil, {name, _address}} -> name
        {nil, _address} -> URI.parse(campaigns.url).host
      end
    end

    defp sender(%Campaign{from_name: name}, %{from: from}) when is_binary(name),
      do: {name, address(from)}

    defp sender(_campaign, %{from: from}), do: from

    defp address({_name, address}), do: address
    defp address(address), do: address

    # ── Merge tags ────────────────────────────────────────────────

    @doc "The merge tags the letters of a campaign use, by name."
    @spec tags(Campaign.t()) :: [String.t()]
    def tags(%Campaign{} = campaign) do
      config = Config.get()
      campaign = Tayori.Campaigns.with_steps(config, campaign)

      for step <- campaign.steps,
          letter <- step.letters,
          field <- [
            letter.subject,
            letter.preheader,
            letter.body && letter.body.html,
            letter.cta_label,
            letter.cta_url
          ],
          is_binary(field),
          [_, name | _] <- Regex.scan(@tag, field),
          uniq: true do
        name
      end
      |> Enum.sort()
    end

    @doc "The merge tags of a campaign that a person has no value for."
    @spec missing(Campaign.t(), Recipient.t()) :: [String.t()]
    def missing(%Campaign{} = campaign, %Recipient{} = recipient) do
      values = values(recipient)
      Enum.reject(tags(campaign), &value(values, &1))
    end

    defp values(%Recipient{} = recipient) do
      data = Map.new(recipient.data || %{}, fn {key, value} -> {to_string(key), value} end)
      Map.merge(data, %{"name" => recipient.name, "email" => recipient.email})
    end

    defp value(values, key) do
      case Map.get(values, key) do
        nil -> nil
        "" -> nil
        value when is_binary(value) -> value
        value when is_number(value) or is_boolean(value) or is_atom(value) -> to_string(value)
        _other -> nil
      end
    end

    @doc false
    # Tags in plain text: their values, or their fallbacks.
    @spec merge(String.t(), map()) :: String.t()
    def merge(text, values) do
      Regex.replace(@tag, text, fn _whole, key, fallback -> value(values, key) || fallback end)
    end

    # Tags in HTML: in the links first, as addresses, then in the text,
    # escaped. A fallback is the letter's own HTML, as it is.
    defp merge_html(html, values) do
      html =
        Regex.replace(~r/\s(href|src)="([^"]*)"/, html, fn _whole, attribute, url ->
          ~s( #{attribute}="#{merge_url(url, values, &Layout.escape/1)}")
        end)

      Regex.replace(@tag, html, fn _whole, key, fallback ->
        case value(values, key) do
          nil -> fallback
          value -> Layout.escape(value)
        end
      end)
    end

    # A tag at the start of an address is an address, or nothing; one
    # after it is a part of it.
    defp merge_url(url, values, escape) do
      {start, rest} =
        case Regex.run(@leading_tag, url, return: :index) do
          [{0, length} | _] ->
            [_, key | fallback] = Regex.run(@leading_tag, url)
            value = value(values, key) || List.first(fallback, "")
            start = if address?(value), do: escape.(value), else: ""
            {start, binary_part(url, length, byte_size(url) - length)}

          nil ->
            {"", url}
        end

      start <>
        Regex.replace(@tag, rest, fn _whole, key, fallback ->
          case value(values, key) do
            nil -> fallback
            value -> escape.(URI.encode_www_form(value))
          end
        end)
    end

    defp address?(value), do: http?(value) or String.starts_with?(value, "mailto:")

    defp http?(url) do
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and host not in [nil, ""] ->
          true

        _ ->
          false
      end
    end

    # ── Unsubscribing ─────────────────────────────────────────────

    @doc "The link to unsubscribe an address from a purpose."
    @spec unsubscribe_url(String.t(), String.t()) :: String.t()
    def unsubscribe_url(email, purpose) do
      Config.get().campaigns.url <> "/unsubscribe/" <> token(email, purpose)
    end

    @doc "The token of the link to unsubscribe an address from a purpose."
    @spec token(String.t(), String.t()) :: String.t()
    def token(email, purpose) when is_binary(email) and is_binary(purpose) do
      Phoenix.Token.sign(Config.get().secret_key_base, @salt, %{
        "e" => String.downcase(String.trim(email)),
        "p" => purpose
      })
    end

    @doc "The address and purpose of a token, or `:error`."
    @spec verify(String.t()) :: {:ok, %{email: String.t(), purpose: String.t()}} | :error
    def verify(token) when is_binary(token) do
      case Phoenix.Token.verify(Config.get().secret_key_base, @salt, token, max_age: :infinity) do
        {:ok, %{"e" => email, "p" => purpose}}
        when is_binary(email) and purpose in ["product", "marketing", "all"] ->
          {:ok, %{email: email, purpose: purpose}}

        _ ->
          :error
      end
    end
  end
end
