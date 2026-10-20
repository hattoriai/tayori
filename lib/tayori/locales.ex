defmodule Tayori.Locales do
  @moduledoc """
  The names of the languages of the entries, in their own language, for
  the admin's tabs and the readers' language links.

  ## Examples

      iex> Tayori.Locales.name("pt-PT")
      "Português (Portugal)"

      iex> Tayori.Locales.name("ja")
      "日本語"

      iex> Tayori.Locales.name("es-ES")
      "Español"

      iex> Tayori.Locales.name("tlh")
      "tlh"

  """

  @names %{
    "ar" => "العربية",
    "ca" => "Català",
    "cs" => "Čeština",
    "da" => "Dansk",
    "de" => "Deutsch",
    "el" => "Ελληνικά",
    "en" => "English",
    "en-GB" => "English (UK)",
    "en-US" => "English (US)",
    "es" => "Español",
    "fi" => "Suomi",
    "fr" => "Français",
    "he" => "עברית",
    "hi" => "हिन्दी",
    "hu" => "Magyar",
    "id" => "Bahasa Indonesia",
    "it" => "Italiano",
    "ja" => "日本語",
    "ko" => "한국어",
    "nb" => "Norsk bokmål",
    "nl" => "Nederlands",
    "pl" => "Polski",
    "pt" => "Português",
    "pt-BR" => "Português (Brasil)",
    "pt-PT" => "Português (Portugal)",
    "ro" => "Română",
    "ru" => "Русский",
    "sv" => "Svenska",
    "th" => "ไทย",
    "tr" => "Türkçe",
    "uk" => "Українська",
    "vi" => "Tiếng Việt",
    "zh" => "中文",
    "zh-Hans" => "简体中文",
    "zh-Hant" => "繁體中文"
  }

  @doc """
  The name of a language in its own language: of the locale, else of its
  language (`es-ES` is Español), else its tag when Tayori does not know it.
  """
  @spec name(String.t()) :: String.t()
  def name(locale) do
    Map.get_lazy(@names, locale, fn ->
      Map.get(@names, locale |> String.split(["-", "_"]) |> hd(), locale)
    end)
  end
end
