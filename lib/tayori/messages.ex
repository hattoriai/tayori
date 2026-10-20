defmodule Tayori.Messages do
  @moduledoc """
  The words around the news: the button, the panel, the public page and
  the feeds ("What's new", "Show more"). The entries are the app's own,
  written in the admin in each language.

  The words are here in English, Portuguese, Spanish, French, German,
  Italian, Dutch and Japanese; a locale with a region (`pt-BR`, `en-GB`)
  takes the words of its language, and another language gets English.

  Give other words in the config, by locale or language:

      config :tayori, messages: %{"en" => %{"title" => "Changelog"}}

  or to a component, as `messages`. A word may have `{n}`, which is
  filled with a count; the keys that end in `One` and `Other` are the
  forms of a count. `date` is the pattern of a day (`{d}`, `{m}`, `{y}`,
  `{month}`), and `months` the names of the months, separated by commas.
  """

  @english %{
    "title" => "What's new",
    "button" => "What's new",
    "unreadOne" => "{n} new update",
    "unreadOther" => "{n} new updates",
    "close" => "Close",
    "empty" => "No news yet.",
    "more" => "Show more",
    "readMore" => "Read more",
    "allNews" => "All the news",
    "new" => "New",
    "feed" => "Feed",
    "loading" => "Loading…",
    "date" => "{d} {month} {y}",
    "months" =>
      "January,February,March,April,May,June,July,August,September,October,November,December"
  }

  @translations %{
    "pt" => %{
      "title" => "Novidades",
      "button" => "Novidades",
      "unreadOne" => "{n} novidade",
      "unreadOther" => "{n} novidades",
      "close" => "Fechar",
      "empty" => "Ainda não há novidades.",
      "more" => "Ver mais",
      "readMore" => "Ler mais",
      "allNews" => "Todas as novidades",
      "new" => "Novo",
      "feed" => "Feed",
      "loading" => "A carregar…",
      "date" => "{d} de {month} de {y}",
      "months" =>
        "janeiro,fevereiro,março,abril,maio,junho,julho,agosto,setembro,outubro,novembro,dezembro"
    },
    "es" => %{
      "title" => "Novedades",
      "button" => "Novedades",
      "unreadOne" => "{n} novedad",
      "unreadOther" => "{n} novedades",
      "close" => "Cerrar",
      "empty" => "Aún no hay novedades.",
      "more" => "Ver más",
      "readMore" => "Leer más",
      "allNews" => "Todas las novedades",
      "new" => "Nuevo",
      "feed" => "Feed",
      "loading" => "Cargando…",
      "date" => "{d} de {month} de {y}",
      "months" =>
        "enero,febrero,marzo,abril,mayo,junio,julio,agosto,septiembre,octubre,noviembre,diciembre"
    },
    "fr" => %{
      "title" => "Nouveautés",
      "button" => "Nouveautés",
      "unreadOne" => "{n} nouveauté",
      "unreadOther" => "{n} nouveautés",
      "close" => "Fermer",
      "empty" => "Pas encore de nouveautés.",
      "more" => "Voir plus",
      "readMore" => "Lire la suite",
      "allNews" => "Toutes les nouveautés",
      "new" => "Nouveau",
      "feed" => "Flux",
      "loading" => "Chargement…",
      "date" => "{d} {month} {y}",
      "months" =>
        "janvier,février,mars,avril,mai,juin,juillet,août,septembre,octobre,novembre,décembre"
    },
    "de" => %{
      "title" => "Neuigkeiten",
      "button" => "Neuigkeiten",
      "unreadOne" => "{n} Neuigkeit",
      "unreadOther" => "{n} Neuigkeiten",
      "close" => "Schließen",
      "empty" => "Noch keine Neuigkeiten.",
      "more" => "Mehr anzeigen",
      "readMore" => "Weiterlesen",
      "allNews" => "Alle Neuigkeiten",
      "new" => "Neu",
      "feed" => "Feed",
      "loading" => "Wird geladen …",
      "date" => "{d}. {month} {y}",
      "months" =>
        "Januar,Februar,März,April,Mai,Juni,Juli,August,September,Oktober,November,Dezember"
    },
    "it" => %{
      "title" => "Novità",
      "button" => "Novità",
      "unreadOne" => "{n} novità",
      "unreadOther" => "{n} novità",
      "close" => "Chiudi",
      "empty" => "Ancora nessuna novità.",
      "more" => "Mostra altro",
      "readMore" => "Continua a leggere",
      "allNews" => "Tutte le novità",
      "new" => "Nuovo",
      "feed" => "Feed",
      "loading" => "Caricamento…",
      "date" => "{d} {month} {y}",
      "months" =>
        "gennaio,febbraio,marzo,aprile,maggio,giugno,luglio,agosto,settembre,ottobre,novembre,dicembre"
    },
    "nl" => %{
      "title" => "Nieuw",
      "button" => "Nieuw",
      "unreadOne" => "{n} nieuwe update",
      "unreadOther" => "{n} nieuwe updates",
      "close" => "Sluiten",
      "empty" => "Nog geen nieuws.",
      "more" => "Meer tonen",
      "readMore" => "Verder lezen",
      "allNews" => "Al het nieuws",
      "new" => "Nieuw",
      "feed" => "Feed",
      "loading" => "Laden…",
      "date" => "{d} {month} {y}",
      "months" =>
        "januari,februari,maart,april,mei,juni,juli,augustus,september,oktober,november,december"
    },
    "ja" => %{
      "title" => "お知らせ",
      "button" => "お知らせ",
      "unreadOne" => "新着{n}件",
      "unreadOther" => "新着{n}件",
      "close" => "閉じる",
      "empty" => "お知らせはまだありません。",
      "more" => "もっと見る",
      "readMore" => "続きを読む",
      "allNews" => "すべてのお知らせ",
      "new" => "新着",
      "feed" => "フィード",
      "loading" => "読み込み中…",
      "date" => "{y}年{m}月{d}日",
      "months" => "1月,2月,3月,4月,5月,6月,7月,8月,9月,10月,11月,12月"
    }
  }

  @doc """
  The keys of the words.

  ## Examples

      iex> "title" in Tayori.Messages.keys()
      true

  """
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(@english)

  @doc """
  The words for a locale: the built-in words of its language, then those
  of the config for the language and for the locale, then `overrides`.

  ## Examples

      iex> Tayori.Messages.for_locale("pt-PT")["title"]
      "Novidades"

      iex> Tayori.Messages.for_locale("sv")["title"]
      "What's new"

      iex> Tayori.Messages.for_locale("en", %{"title" => "Changelog"})["title"]
      "Changelog"

  """
  @spec for_locale(String.t() | nil, map()) :: %{String.t() => String.t()}
  def for_locale(locale, overrides \\ %{}) do
    locale = locale || "en"
    language = locale |> String.split("-") |> hd()
    config = Application.get_env(:tayori, :messages, %{})

    @english
    |> Map.merge(Map.get(@translations, language, %{}))
    |> Map.merge(Map.get(config, language, %{}))
    |> Map.merge(Map.get(config, locale, %{}))
    |> Map.merge(overrides || %{})
  end

  @doc """
  A day in words, in the language of the messages.

  ## Examples

      iex> Tayori.Messages.date(Tayori.Messages.for_locale("en"), ~U[2026-10-20 09:00:00Z])
      "20 October 2026"

      iex> Tayori.Messages.date(Tayori.Messages.for_locale("pt-PT"), ~D[2026-03-01])
      "1 de março de 2026"

      iex> Tayori.Messages.date(Tayori.Messages.for_locale("ja"), ~D[2026-03-01])
      "2026年3月1日"

  """
  @spec date(map(), Date.t() | DateTime.t()) :: String.t()
  def date(messages, %DateTime{} = at), do: date(messages, DateTime.to_date(at))

  def date(messages, %Date{year: y, month: m, day: d}) do
    month = messages["months"] |> String.split(",") |> Enum.at(m - 1)

    messages["date"]
    |> String.replace("{d}", Integer.to_string(d))
    |> String.replace("{m}", Integer.to_string(m))
    |> String.replace("{y}", Integer.to_string(y))
    |> String.replace("{month}", month)
  end

  @doc """
  The count of unread entries in words.

  ## Examples

      iex> Tayori.Messages.unread(Tayori.Messages.for_locale("en"), 1)
      "1 new update"

      iex> Tayori.Messages.unread(Tayori.Messages.for_locale("pt"), 3)
      "3 novidades"

  """
  @spec unread(map(), non_neg_integer()) :: String.t()
  def unread(messages, n) do
    key = if n == 1, do: "unreadOne", else: "unreadOther"
    String.replace(messages[key], "{n}", Integer.to_string(n))
  end
end
