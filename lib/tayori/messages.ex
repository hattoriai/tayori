defmodule Tayori.Messages do
  @moduledoc """
  The words around the news: the button, the panel, the public page and
  the feeds ("What's new", "Show more"); and of the campaigns' letters,
  their footer and the page to unsubscribe. The entries and the letters
  are the app's own, written in the admin in each language.

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
    "back" => "Back",
    "categories" => "Categories",
    "all" => "All",
    "pinned" => "Pinned",
    "react" => "React to this update",
    "signInToReact" => "Sign in to react",
    "tryIt" => "Try it",
    "dismiss" => "Dismiss",
    "search" => "Search",
    "searchPlaceholder" => "Search the news",
    "noResults" => "Nothing matches your search.",
    "clearSearch" => "Clear the search",
    "subscribe" => "Subscribe",
    "subscribeTitle" => "Get the news by email",
    "subscribeText" => "The news, by email. Unsubscribe at any time.",
    "email" => "Email address",
    "emailPlaceholder" => "you@example.com",
    "subscribed" => "Almost there: check your inbox to confirm your address.",
    "confirmed" => "You're subscribed. The next update comes to your inbox.",
    "unsubscribed" => "You're unsubscribed. No more emails.",
    "invalidLink" => "This link does not work any more.",
    "unsubscribeAll" => "Unsubscribe from everything",
    "unsubscribeMarketing" => "Stop the news and offers sent to {email}?",
    "unsubscribeProduct" => "Stop the tips and updates about the product sent to {email}?",
    "unsubscribeEverything" => "Stop every email of these letters to {email}?",
    "unsubscribedLetters" => "You're unsubscribed. These emails stop here.",
    "unsubscribedAll" => "You're unsubscribed from everything. No more emails.",
    "older" => "Older updates",
    "newer" => "Newer updates",
    "previous" => "Previous",
    "next" => "Next",
    "notPublished" => "Preview: this update is not published yet.",
    "confirmSubject" => "Confirm your subscription",
    "confirmText" => "Confirm your address to get the news by email.",
    "confirmButton" => "Confirm my address",
    "confirmIgnore" => "If you did not ask for this, ignore this email.",
    "readOnline" => "Read it online",
    "unsubscribe" => "Unsubscribe",
    "language" => "Language",
    "shareLink" => "Copy link",
    "copied" => "Copied",
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
      "back" => "Voltar",
      "categories" => "Categorias",
      "all" => "Todas",
      "pinned" => "Fixada",
      "react" => "Reagir a esta novidade",
      "signInToReact" => "Inicie sessão para reagir",
      "tryIt" => "Experimentar",
      "dismiss" => "Dispensar",
      "search" => "Pesquisar",
      "searchPlaceholder" => "Pesquisar as novidades",
      "noResults" => "Nada corresponde à sua pesquisa.",
      "clearSearch" => "Limpar a pesquisa",
      "subscribe" => "Subscrever",
      "subscribeTitle" => "Receba as novidades por email",
      "subscribeText" => "As novidades, por email. Pode cancelar quando quiser.",
      "email" => "Endereço de email",
      "emailPlaceholder" => "nome@exemplo.com",
      "subscribed" => "Quase: confirme o seu endereço no email que lhe enviámos.",
      "confirmed" => "Subscrição confirmada. A próxima novidade chega ao seu email.",
      "unsubscribed" => "Subscrição cancelada. Não receberá mais emails.",
      "invalidLink" => "Este link já não funciona.",
      "unsubscribeAll" => "Cancelar a subscrição de tudo",
      "unsubscribeMarketing" => "Deixar de receber novidades e ofertas em {email}?",
      "unsubscribeProduct" => "Deixar de receber dicas e notícias sobre o produto em {email}?",
      "unsubscribeEverything" => "Deixar de receber todos estes emails em {email}?",
      "unsubscribedLetters" => "Subscrição cancelada. Estes emails terminam aqui.",
      "unsubscribedAll" => "Subscrição de tudo cancelada. Não receberá mais emails.",
      "older" => "Novidades anteriores",
      "newer" => "Novidades mais recentes",
      "previous" => "Anterior",
      "next" => "Seguinte",
      "notPublished" => "Pré-visualização: esta novidade ainda não foi publicada.",
      "confirmSubject" => "Confirme a sua subscrição",
      "confirmText" => "Confirme o seu endereço para receber as novidades por email.",
      "confirmButton" => "Confirmar o meu endereço",
      "confirmIgnore" => "Se não pediu isto, ignore este email.",
      "readOnline" => "Ler online",
      "unsubscribe" => "Cancelar a subscrição",
      "language" => "Idioma",
      "shareLink" => "Copiar link",
      "copied" => "Copiado",
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
      "back" => "Volver",
      "categories" => "Categorías",
      "all" => "Todas",
      "pinned" => "Fijada",
      "react" => "Reaccionar a esta novedad",
      "signInToReact" => "Inicia sesión para reaccionar",
      "tryIt" => "Probar",
      "dismiss" => "Descartar",
      "search" => "Buscar",
      "searchPlaceholder" => "Buscar en las novedades",
      "noResults" => "Nada coincide con tu búsqueda.",
      "clearSearch" => "Borrar la búsqueda",
      "subscribe" => "Suscribirse",
      "subscribeTitle" => "Recibe las novedades por email",
      "subscribeText" => "Las novedades, por email. Puedes darte de baja cuando quieras.",
      "email" => "Dirección de email",
      "emailPlaceholder" => "tu@ejemplo.com",
      "subscribed" => "Casi listo: revisa tu bandeja de entrada para confirmar tu dirección.",
      "confirmed" => "Te has suscrito. La próxima novedad llegará a tu bandeja de entrada.",
      "unsubscribed" => "Te has dado de baja. No recibirás más emails.",
      "invalidLink" => "Este enlace ya no funciona.",
      "unsubscribeAll" => "Darse de baja de todo",
      "unsubscribeMarketing" => "¿Dejar de recibir novedades y ofertas en {email}?",
      "unsubscribeProduct" => "¿Dejar de recibir consejos y novedades del producto en {email}?",
      "unsubscribeEverything" => "¿Dejar de recibir todos estos emails en {email}?",
      "unsubscribedLetters" => "Te has dado de baja. Estos emails terminan aquí.",
      "unsubscribedAll" => "Te has dado de baja de todo. No recibirás más emails.",
      "older" => "Novedades anteriores",
      "newer" => "Novedades más recientes",
      "previous" => "Anterior",
      "next" => "Siguiente",
      "notPublished" => "Vista previa: esta novedad aún no está publicada.",
      "confirmSubject" => "Confirma tu suscripción",
      "confirmText" => "Confirma tu dirección para recibir las novedades por email.",
      "confirmButton" => "Confirmar mi dirección",
      "confirmIgnore" => "Si no lo has pedido, ignora este email.",
      "readOnline" => "Leer online",
      "unsubscribe" => "Darse de baja",
      "language" => "Idioma",
      "shareLink" => "Copiar enlace",
      "copied" => "Copiado",
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
      "back" => "Retour",
      "categories" => "Catégories",
      "all" => "Toutes",
      "pinned" => "Épinglée",
      "react" => "Réagir à cette nouveauté",
      "signInToReact" => "Connectez-vous pour réagir",
      "tryIt" => "Essayer",
      "dismiss" => "Ignorer",
      "search" => "Rechercher",
      "searchPlaceholder" => "Rechercher dans les nouveautés",
      "noResults" => "Rien ne correspond à votre recherche.",
      "clearSearch" => "Effacer la recherche",
      "subscribe" => "S'abonner",
      "subscribeTitle" => "Recevez les nouveautés par email",
      "subscribeText" => "Les nouveautés, par email. Désabonnement à tout moment.",
      "email" => "Adresse email",
      "emailPlaceholder" => "vous@exemple.com",
      "subscribed" =>
        "Presque fini : confirmez votre adresse dans l'email que nous venons d'envoyer.",
      "confirmed" => "Vous êtes abonné. La prochaine nouveauté arrivera dans votre boîte.",
      "unsubscribed" => "Vous êtes désabonné. Plus d'emails.",
      "invalidLink" => "Ce lien ne fonctionne plus.",
      "unsubscribeAll" => "Se désabonner de tout",
      "unsubscribeMarketing" => "Ne plus recevoir les nouvelles et les offres à {email} ?",
      "unsubscribeProduct" => "Ne plus recevoir les conseils et nouvelles du produit à {email} ?",
      "unsubscribeEverything" => "Ne plus recevoir aucun de ces emails à {email} ?",
      "unsubscribedLetters" => "Vous êtes désabonné. Ces emails s'arrêtent ici.",
      "unsubscribedAll" => "Vous êtes désabonné de tout. Plus d'emails.",
      "older" => "Nouveautés précédentes",
      "newer" => "Nouveautés plus récentes",
      "previous" => "Précédente",
      "next" => "Suivante",
      "notPublished" => "Aperçu : cette nouveauté n'est pas encore publiée.",
      "confirmSubject" => "Confirmez votre abonnement",
      "confirmText" => "Confirmez votre adresse pour recevoir les nouveautés par email.",
      "confirmButton" => "Confirmer mon adresse",
      "confirmIgnore" => "Si vous n'avez rien demandé, ignorez cet email.",
      "readOnline" => "Lire en ligne",
      "unsubscribe" => "Se désabonner",
      "language" => "Langue",
      "shareLink" => "Copier le lien",
      "copied" => "Copié",
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
      "back" => "Zurück",
      "categories" => "Kategorien",
      "all" => "Alle",
      "pinned" => "Angeheftet",
      "react" => "Auf diese Neuigkeit reagieren",
      "signInToReact" => "Melde dich an, um zu reagieren",
      "tryIt" => "Ausprobieren",
      "dismiss" => "Schließen",
      "search" => "Suchen",
      "searchPlaceholder" => "Neuigkeiten durchsuchen",
      "noResults" => "Nichts passt zu deiner Suche.",
      "clearSearch" => "Suche löschen",
      "subscribe" => "Abonnieren",
      "subscribeTitle" => "Neuigkeiten per E-Mail",
      "subscribeText" => "Die Neuigkeiten per E-Mail. Jederzeit abbestellbar.",
      "email" => "E-Mail-Adresse",
      "emailPlaceholder" => "du@beispiel.de",
      "subscribed" =>
        "Fast geschafft: Bestätige deine Adresse in der E-Mail, die wir dir geschickt haben.",
      "confirmed" => "Du hast abonniert. Die nächste Neuigkeit kommt in dein Postfach.",
      "unsubscribed" => "Du hast abbestellt. Keine E-Mails mehr.",
      "invalidLink" => "Dieser Link funktioniert nicht mehr.",
      "unsubscribeAll" => "Alles abbestellen",
      "unsubscribeMarketing" => "Keine Neuigkeiten und Angebote mehr an {email}?",
      "unsubscribeProduct" => "Keine Tipps und Neuigkeiten zum Produkt mehr an {email}?",
      "unsubscribeEverything" => "Keine dieser E-Mails mehr an {email}?",
      "unsubscribedLetters" => "Du hast abbestellt. Diese E-Mails hören hier auf.",
      "unsubscribedAll" => "Du hast alles abbestellt. Keine E-Mails mehr.",
      "older" => "Ältere Neuigkeiten",
      "newer" => "Neuere Neuigkeiten",
      "previous" => "Vorherige",
      "next" => "Nächste",
      "notPublished" => "Vorschau: Diese Neuigkeit ist noch nicht veröffentlicht.",
      "confirmSubject" => "Bestätige dein Abonnement",
      "confirmText" => "Bestätige deine Adresse, um die Neuigkeiten per E-Mail zu erhalten.",
      "confirmButton" => "Adresse bestätigen",
      "confirmIgnore" => "Wenn du das nicht angefordert hast, ignoriere diese E-Mail.",
      "readOnline" => "Online lesen",
      "unsubscribe" => "Abbestellen",
      "language" => "Sprache",
      "shareLink" => "Link kopieren",
      "copied" => "Kopiert",
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
      "back" => "Indietro",
      "categories" => "Categorie",
      "all" => "Tutte",
      "pinned" => "In evidenza",
      "react" => "Reagisci a questa novità",
      "signInToReact" => "Accedi per reagire",
      "tryIt" => "Provalo",
      "dismiss" => "Chiudi",
      "search" => "Cerca",
      "searchPlaceholder" => "Cerca nelle novità",
      "noResults" => "Nessun risultato per la tua ricerca.",
      "clearSearch" => "Cancella la ricerca",
      "subscribe" => "Iscriviti",
      "subscribeTitle" => "Ricevi le novità via email",
      "subscribeText" => "Le novità, via email. Puoi annullare quando vuoi.",
      "email" => "Indirizzo email",
      "emailPlaceholder" => "tu@esempio.it",
      "subscribed" =>
        "Ci siamo quasi: conferma il tuo indirizzo nell'email che ti abbiamo inviato.",
      "confirmed" => "Sei iscritto. La prossima novità arriverà nella tua casella.",
      "unsubscribed" => "Iscrizione annullata. Niente più email.",
      "invalidLink" => "Questo link non funziona più.",
      "unsubscribeAll" => "Annulla tutte le iscrizioni",
      "unsubscribeMarketing" => "Non ricevere più novità e offerte su {email}?",
      "unsubscribeProduct" => "Non ricevere più consigli e novità sul prodotto su {email}?",
      "unsubscribeEverything" => "Non ricevere più nessuna di queste email su {email}?",
      "unsubscribedLetters" => "Iscrizione annullata. Queste email finiscono qui.",
      "unsubscribedAll" => "Tutte le iscrizioni annullate. Niente più email.",
      "older" => "Novità precedenti",
      "newer" => "Novità più recenti",
      "previous" => "Precedente",
      "next" => "Successiva",
      "notPublished" => "Anteprima: questa novità non è ancora pubblicata.",
      "confirmSubject" => "Conferma la tua iscrizione",
      "confirmText" => "Conferma il tuo indirizzo per ricevere le novità via email.",
      "confirmButton" => "Conferma il mio indirizzo",
      "confirmIgnore" => "Se non l'hai chiesto tu, ignora questa email.",
      "readOnline" => "Leggi online",
      "unsubscribe" => "Annulla l'iscrizione",
      "language" => "Lingua",
      "shareLink" => "Copia il link",
      "copied" => "Copiato",
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
      "back" => "Terug",
      "categories" => "Categorieën",
      "all" => "Alle",
      "pinned" => "Vastgezet",
      "react" => "Reageer op deze update",
      "signInToReact" => "Log in om te reageren",
      "tryIt" => "Probeer het",
      "dismiss" => "Sluiten",
      "search" => "Zoeken",
      "searchPlaceholder" => "Zoek in het nieuws",
      "noResults" => "Niets komt overeen met je zoekopdracht.",
      "clearSearch" => "Zoekopdracht wissen",
      "subscribe" => "Abonneren",
      "subscribeTitle" => "Ontvang het nieuws per e-mail",
      "subscribeText" => "Het nieuws per e-mail. Altijd af te melden.",
      "email" => "E-mailadres",
      "emailPlaceholder" => "jij@voorbeeld.nl",
      "subscribed" => "Bijna klaar: bevestig je adres via de e-mail die we je stuurden.",
      "confirmed" => "Je bent geabonneerd. De volgende update komt in je inbox.",
      "unsubscribed" => "Je bent afgemeld. Geen e-mails meer.",
      "invalidLink" => "Deze link werkt niet meer.",
      "unsubscribeAll" => "Overal voor afmelden",
      "unsubscribeMarketing" => "Geen nieuws en aanbiedingen meer naar {email}?",
      "unsubscribeProduct" => "Geen tips en nieuws over het product meer naar {email}?",
      "unsubscribeEverything" => "Geen van deze e-mails meer naar {email}?",
      "unsubscribedLetters" => "Je bent afgemeld. Deze e-mails stoppen hier.",
      "unsubscribedAll" => "Je bent overal voor afgemeld. Geen e-mails meer.",
      "older" => "Oudere updates",
      "newer" => "Nieuwere updates",
      "previous" => "Vorige",
      "next" => "Volgende",
      "notPublished" => "Voorbeeld: deze update is nog niet gepubliceerd.",
      "confirmSubject" => "Bevestig je abonnement",
      "confirmText" => "Bevestig je adres om het nieuws per e-mail te ontvangen.",
      "confirmButton" => "Mijn adres bevestigen",
      "confirmIgnore" => "Heb je hier niet om gevraagd? Negeer dan deze e-mail.",
      "readOnline" => "Online lezen",
      "unsubscribe" => "Afmelden",
      "language" => "Taal",
      "shareLink" => "Link kopiëren",
      "copied" => "Gekopieerd",
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
      "back" => "戻る",
      "categories" => "カテゴリ",
      "all" => "すべて",
      "pinned" => "固定",
      "react" => "このお知らせにリアクション",
      "signInToReact" => "リアクションするにはサインインしてください",
      "tryIt" => "試してみる",
      "dismiss" => "閉じる",
      "search" => "検索",
      "searchPlaceholder" => "お知らせを検索",
      "noResults" => "一致するお知らせはありません。",
      "clearSearch" => "検索をクリア",
      "subscribe" => "購読する",
      "subscribeTitle" => "お知らせをメールで受け取る",
      "subscribeText" => "お知らせをメールでお届けします。いつでも解除できます。",
      "email" => "メールアドレス",
      "emailPlaceholder" => "you@example.com",
      "subscribed" => "あと少しです。届いたメールでアドレスを確認してください。",
      "confirmed" => "購読しました。次のお知らせはメールで届きます。",
      "unsubscribed" => "購読を解除しました。今後メールは届きません。",
      "invalidLink" => "このリンクは無効になりました。",
      "unsubscribeAll" => "すべての購読を解除",
      "unsubscribeMarketing" => "{email} へのお知らせとご案内の配信を停止しますか？",
      "unsubscribeProduct" => "{email} への製品のヒントと最新情報の配信を停止しますか？",
      "unsubscribeEverything" => "{email} へのこれらのメールの配信をすべて停止しますか？",
      "unsubscribedLetters" => "購読を解除しました。これらのメールは今後届きません。",
      "unsubscribedAll" => "すべての購読を解除しました。今後メールは届きません。",
      "older" => "以前のお知らせ",
      "newer" => "新しいお知らせ",
      "previous" => "前へ",
      "next" => "次へ",
      "notPublished" => "プレビュー：このお知らせはまだ公開されていません。",
      "confirmSubject" => "購読の確認",
      "confirmText" => "メールでお知らせを受け取るには、アドレスを確認してください。",
      "confirmButton" => "アドレスを確認する",
      "confirmIgnore" => "心当たりがない場合は、このメールを無視してください。",
      "readOnline" => "オンラインで読む",
      "unsubscribe" => "購読を解除",
      "language" => "言語",
      "shareLink" => "リンクをコピー",
      "copied" => "コピーしました",
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
