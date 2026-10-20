defmodule TayoriDev.Seeds do
  @moduledoc """
  Atelier's news, the first time the dev server starts: eight entries
  that use every style an entry can hold, with the screenshots and files
  of dev/seed/ stored as Kotoba stores the files of an upload; categories,
  a cover on some, a pin, an announcement, reactions and views.

  The styles Markdown has no syntax for are written as markers and turned
  into Kotoba's own document: `{red|Blocked}` is a text color, and a table
  marked `<!-- header-column -->` gets a header column.
  """

  alias Tayori.{Categories, Entries}

  @seed Path.expand("seed", __DIR__)
  @author %{"id" => 1, "name" => "Hattori Hanzo"}

  def run do
    if Entries.list() == [] do
      categories()
      shots = store_all()
      entries = Enum.map(entries(shots), &entry/1)
      reactions(entries)
      views(entries)
    end

    :ok
  end

  defp categories do
    for {key, en, pt, color} <- [
          {"new", "New", "Novo", "blue"},
          {"improved", "Improved", "Melhorado", "green"},
          {"fixed", "Fixed", "Corrigido", "orange"},
          {"api", "API", "API", "purple"},
          {"announcement", "Announcement", "Anúncio", "amber"}
        ] do
      {:ok, _} = Categories.create(%{"key" => key, "names" => %{"en" => en, "pt-PT" => pt}, "color" => color})
    end
  end

  # Every file of dev/seed, stored as an upload stores it.
  defp store_all do
    images =
      for file <- File.ls!(Path.join(@seed, "images")), into: %{} do
        {Path.rootname(file), store(Path.join([@seed, "images", file]))}
      end

    files =
      for file <- File.ls!(Path.join(@seed, "files")), into: %{} do
        {Path.rootname(file), store(Path.join([@seed, "files", file]))}
      end

    Map.merge(images, files)
  end

  defp store(path) do
    {:ok, node} = Kotoba.Attachments.store(path, storage: Kotoba.Storage.Local)
    node
  end

  defp entry(spec) do
    translations =
      for {locale, t} <- spec.translations do
        %{
          "locale" => locale,
          "title" => t.title,
          "summary" => t[:summary],
          "body" => content(t.body, spec.shots, spec[:tables] || %{}),
          "cta_label" => t[:cta_label],
          "cta_url" => t[:cta_url]
        }
      end

    {:ok, entry} =
      Entries.create(
        %{
          "slug" => spec[:slug],
          "categories" => spec.categories,
          "segments" => spec[:segments] || [],
          "announce" => spec[:announce],
          "announce_until" => spec[:announce_until],
          "email" => spec[:email] || false,
          "translations" => translations
        },
        author: @author
      )

    {:ok, entry} =
      if cover = spec[:cover],
        do: Entries.put_cover(entry, cover, spec[:cover_alt]),
        else: {:ok, entry}

    {:ok, entry} = if spec[:pinned], do: Entries.pin(entry), else: {:ok, entry}

    case spec[:hours] do
      nil -> entry
      hours -> elem(Entries.publish(entry, DateTime.add(DateTime.utc_now(), round(hours * 3600))), 1)
    end
  end

  # Markdown with attachments, then the markers of what Markdown cannot say.
  defp content(markdown, shots, tables) do
    %Kotoba.Content{doc: doc} = Kotoba.Content.from_markdown(markdown, attachments: shots)
    doc = update_in(doc, ["root"], &walk(&1, tables))
    {:ok, content} = Kotoba.Content.cast(doc)
    content
  end

  defp walk(%{"type" => "table"} = table, tables) do
    table = Map.update(table, "children", [], fn rows -> Enum.map(rows, &walk(&1, tables)) end)
    first_text = table |> text_of() |> String.trim()

    case Enum.find(tables, fn {start, _mode} -> String.starts_with?(first_text, start) end) do
      {_start, mode} -> header_column(table, mode)
      nil -> table
    end
  end

  defp walk(%{"children" => children} = node, tables) do
    %{node | "children" => Enum.flat_map(children, &colorize/1) |> Enum.map(&walk(&1, tables))}
  end

  defp walk(node, _tables), do: node

  # {red|Blocked}: a run of text in a color of Kotoba's palette.
  defp colorize(%{"type" => "text", "text" => text} = node) do
    ~r/\{(red|orange|yellow|green|blue|purple|gray)\|([^}]+)\}/
    |> Regex.split(text, include_captures: true)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn part ->
      case Regex.run(~r/\A\{(\w+)\|([^}]+)\}\z/, part) do
        [_, color, words] ->
          %{node | "text" => words, "style" => "color: var(--kotoba-color-#{color});"}

        nil ->
          %{node | "text" => part}
      end
    end)
  end

  defp colorize(node), do: [node]

  defp text_of(%{"text" => text}), do: text
  defp text_of(%{"children" => children}), do: Enum.map_join(children, " ", &text_of/1)
  defp text_of(_node), do: ""

  # The first cell of each row is a header; :both keeps the header row.
  defp header_column(table, mode) do
    rows =
      table["children"]
      |> Enum.with_index()
      |> Enum.map(fn {row, r} -> %{row | "children" => header_cells(row["children"], r, mode)} end)

    %{table | "children" => rows}
  end

  defp header_cells(cells, r, mode) do
    for {cell, c} <- Enum.with_index(cells) do
      row_bit = if r == 0 and mode == :both, do: 1, else: 0
      column_bit = if c == 0, do: 2, else: 0
      %{cell | "headerState" => Bitwise.bor(row_bit, column_bit)}
    end
  end

  defp reactions(entries) do
    emoji = Tayori.Config.get().reactions

    for {entry, i} <- Enum.with_index(entries), entry.published_at,
        DateTime.compare(entry.published_at, DateTime.utc_now()) == :lt,
        reader <- 1..(14 - i * 2)//1,
        e <- Enum.take(emoji, rem(reader + i, length(emoji)) + 1) do
      Tayori.Reactions.toggle(%Tayori.Reader{id: "seed:#{reader}"}, entry.id, e)
    end
  end

  # A month of views, from each place, so that the stats have a shape.
  defp views(entries) do
    config = Tayori.Config.get()
    today = Date.utc_today()

    rows =
      for {entry, i} <- Enum.with_index(entries),
          entry.published_at,
          DateTime.compare(entry.published_at, DateTime.utc_now()) == :lt,
          days_ago <- 0..min(29, max(0, Date.diff(today, DateTime.to_date(entry.published_at)))),
          {source, weight} <- [{"panel", 9}, {"page", 4}, {"email", 2}, {"feed", 1}],
          reader <- ["", "seed:#{rem(days_ago * 7 + i, 23)}"] do
        %{
          entry_id: entry.id,
          reader: reader,
          source: source,
          day: Date.add(today, -days_ago),
          count: max(1, round(weight * (30 - days_ago) / 6) - i)
        }
      end

    rows
    |> Enum.uniq_by(&{&1.entry_id, &1.reader, &1.source, &1.day})
    |> Enum.chunk_every(500)
    |> Enum.each(&config.repo.insert_all(Tayori.View, &1, on_conflict: :nothing))
  end

  # ── The entries ─────────────────────────────────────────────────

  defp entries(s) do
    [
      %{
        slug: "timeline-view",
        categories: ["new"],
        hours: -2,
        shots: s,
        cover: s["timeline-week"],
        cover_alt: "Atelier's timeline, a week at a time, with a lane for each person",
        announce: "toast",
        announce_until: DateTime.add(DateTime.utc_now(), 7 * 86_400),
        translations: [
          {"en",
           %{
             title: "Timeline view",
             summary: "See every project's work on one line of time, and drag a task to move its dates.",
             cta_label: "Open the timeline",
             cta_url: "/",
             body: """
             Dates used to live in three places: the board, the calendar and *somebody's
             spreadsheet*. The timeline puts them on one line, a lane for each person, and you
             **drag** a task to move it.

             ![The timeline of the Harbour Museum rebrand](attachment:timeline)

             ## Drag to reschedule

             Grab a task where you see it. The days it moves to light up as you go, and the
             task's dates follow it everywhere else in Atelier.

             - Drag a bar's middle to move it.
             - Drag an edge to change how long it takes.
               - Hold `Shift` to snap to whole weeks.

             ![Dragging a task two days later](attachment:drag-task)

             ## Zoom from days to quarters

             A day for this week's details, a week for the sprint, a quarter for the shape of
             the year.

             ![Day](attachment:timeline-day)
             ![Week](attachment:timeline-week)
             ![Quarter](attachment:timeline-quarter)

             ### Keyboard

             Press `T` on any board to open its timeline, and `←` `→` to move through time.

             ---

             ### Fixes & improvements

             - Board columns keep their width after a reload.
             - File previews open twice as fast.

             Read more in [the Timeline guide](https://example.com/docs/timeline).
             """
           }},
          {"pt-PT",
           %{
             title: "Vista de cronograma",
             summary: "Veja o trabalho de todos os projetos numa só linha do tempo, e arraste uma tarefa para mudar as datas.",
             cta_label: "Abrir o cronograma",
             cta_url: "/",
             body: """
             As datas viviam em três sítios: o quadro, o calendário e *a folha de cálculo de
             alguém*. O cronograma junta-as numa só linha, uma faixa por pessoa, e basta
             **arrastar** uma tarefa para a mudar.

             ![O cronograma do projeto do Museu do Porto](attachment:timeline)

             ## Arraste para reagendar

             - Arraste o meio de uma barra para a mover.
             - Arraste uma ponta para mudar a duração.
               - Mantenha `Shift` premido para avançar semanas inteiras.
             """
           }}
        ]
      },
      %{
        slug: "api-v2",
        categories: ["new", "api"],
        hours: -24,
        shots: s,
        translations: [
          {"en",
           %{
             title: "The Atelier API, version 2",
             summary: "Webhooks, cursor pages and scoped tokens. Version 1 keeps working until 31 March.",
             body: ~S"""
             Version 2 of the API is out, for the studios that connect Atelier to their own
             tools. It has scoped tokens, webhooks and pages that do not skip a project.

             ![A new API token, with its scopes](attachment:api-tokens)

             ## Scoped tokens

             A token now has scopes, and only those: a script that reads projects cannot
             delete files.

             ```bash
             curl -H "Authorization: Bearer $ATELIER_TOKEN" \
               https://api.atelier.test/v2/projects?cursor=eyJpZCI6NDJ9
             ```

             ```json
             {
               "data": [{ "id": "prj_42", "name": "Harbour Museum rebrand" }],
               "next_cursor": "eyJpZCI6NDN9"
             }
             ```

             ## Webhooks

             Atelier tells your app when a card moves, a file lands or a client comments. Each
             request is signed with your webhook's secret:

             ```elixir
             def verify(conn, secret) do
               [signature] = get_req_header(conn, "x-atelier-signature")
               expected = :crypto.mac(:hmac, :sha256, secret, conn.assigns.raw_body)
               Plug.Crypto.secure_compare(Base.encode16(expected, case: :lower), signature)
             end
             ```

             ```javascript
             import { createHmac, timingSafeEqual } from "node:crypto";

             export function verify(body, signature, secret) {
               const expected = createHmac("sha256", secret).update(body).digest("hex");
               return timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
             }
             ```

             ### Endpoints

             | Method | Path | Scope |
             | --- | --- | --- |
             | `GET` | `/v2/projects` | `projects:read` |
             | `POST` | `/v2/files` | `files:write` |
             | `GET` | `/v2/webhooks` | `webhooks:read` |
             | `DELETE` | `/v2/webhooks/:id` | `webhooks:write` |

             ### What changed from version 1

             - ~~`page`~~ and ~~`per_page`~~ are replaced by `cursor`[^1].
             - Dates are ISO 8601, in UTC.

             #### Deprecation

             > **Note:** version 1 answers until 31 March[^2]. Every response from it now
             > carries a `Sunset` header.

             The reference is at https://api.atelier.test/docs

             [^1]: A cursor stays valid for 24 hours.
             [^2]: 2027, at 00:00 UTC.
             """
           }}
        ]
      },
      %{
        slug: "shared-boards",
        categories: ["new"],
        segments: ["plan:pro"],
        hours: -72,
        shots: s,
        cover: s["client-board"],
        cover_alt: "A client's read-only view of a shared board",
        tables: %{"Free Pro" => :both},
        translations: [
          {"en",
           %{
             title: "Shared boards for Pro studios",
             summary: "Share a board with a client, read only, with a link you can turn off.",
             body: """
             Send a client a link to a board. They see it __read only__, as it is now, with
             no account to make and nothing to install.

             ![The Share board dialog](attachment:share-dialog)

             ## What your client sees

             - [x] Cards, their files and due dates
             - [x] Comments marked “client”
             - [ ] Internal notes
             - [ ] Budgets

             ![What the client sees](attachment:client-board)

             ## Status colours

             Cards are {green|Approved}, {orange|In review}, {red|Blocked} or
             {gray|Archived}, and ==the client sees the same colours== you do.

             ## Free and Pro

             |  | Free | Pro |
             | --- | --- | --- |
             | Shared boards | – | Unlimited |
             | Link expiry | – | ✓ |
             | Client comments | – | ✓ |
             """
           }}
        ]
      },
      %{
        slug: "atelier-3-2",
        categories: ["improved", "fixed"],
        hours: -144,
        shots: s,
        translations: [
          {"en",
           %{
             title: "Atelier 3.2",
             summary: "Twenty small things: quicker uploads, a calmer inbox, and fixes from your reports.",
             body: """
             Released 14 October, on desktop, the web and iOS.

             ![Atelier 3.2](/dev-seed/images/release-banner.jpg)

             ## New

             - Quick add: `⌘` `K`, then `N`.
             - Paste an image into a note to attach it.

             ---

             ## Improved

             1. Uploads resume after a lost connection.
             2. The inbox groups by project.
             3. Search remembers the last filter.
             4. Boards:
                - Columns can have a limit.
                - Card covers crop to faces.

             ---

             ## Fixed

             - ~~Dates showed a day early in Auckland.~~ Dates show in your time zone.
             - Exports with emoji in file names open on Windows.
             """
           }}
        ]
      },
      %{
        slug: "faster-search",
        categories: ["improved"],
        hours: -26,
        shots: s,
        translations: [
          {"en",
           %{
             title: "Faster search",
             summary: "Search answers as you type, forgives a typo, and finds words inside PDFs.",
             body: """
             Search answers ==as you type==. It forgives a typo, and it now reads inside your
             PDFs.

             ![Before: a typo and no results](attachment:search-before)
             ![After: results in 35 ms, with a PDF](attachment:search-after)

             ## How much faster

             | Search | Before | After |
             | --- | --- | --- |
             | A project's name | 420 ms | 35 ms |
             | A word in a note | 900 ms | 60 ms |
             | A word in a PDF | – | 80 ms[^1] |

             > We stopped keeping a spreadsheet of where files live.
             >
             > *— Mariana, Estúdio Pátio*

             The tips sheet, if you like to search like a librarian:

             ![Search tips](attachment:search-tips)

             [^1]: The median of a week of searches, in studios with over 10,000 files.
             """
           }}
        ]
      },
      %{
        slug: "exports",
        categories: ["new"],
        hours: -5,
        shots: s,
        email: true,
        translations: [
          {"en",
           %{
             title: "Exports in two clicks",
             summary: "Zip a whole project, with its files, notes and history, and get a link by email.",
             body: """
             ![The Export menu](attachment:export-menu)

             ## How

             1. Open a project.
             2. Choose **Export** in its menu.
             3. Open the link in your email: it lasts **__seven days__**.

             ## What's in the zip

             - [x] Files, in their folders
             - [x] Notes, as Markdown
             - [x] Comments, as CSV

             ```
             harbour-museum/
             ├── files/
             ├── notes/
             └── comments.csv
             ```

             #### Try it

             A sample of the comments:

             ![Comments](attachment:export-sample)
             """
           }},
          {"pt-PT",
           %{
             title: "Exportações em dois cliques",
             summary: "Um zip do projeto inteiro, com ficheiros, notas e histórico, e um link por email.",
             body: """
             ## Como

             1. Abra um projeto.
             2. Escolha **Exportar** no menu.
             3. Abra o link no seu email: dura **__sete dias__**.
             """
           }}
        ]
      },
      %{
        slug: "two-years",
        categories: ["announcement"],
        hours: -960,
        pinned: true,
        shots: s,
        cover: s["studio-desk"],
        cover_alt: "A studio desk: Atelier on a laptop, sketches, swatches and two mugs",
        translations: [
          {"en",
           %{
             title: "Two years of Atelier",
             summary: "A letter from the studio: what we built, what you asked for, and what comes next.",
             body: """
             Two years ago we built Atelier for our own studio, because the tools we had were
             made for software teams. Then you asked to use it too.

             *— Aiko, Ravi and the team*

             ## What we built

             ### In numbers

             - 1,200 studios[^1]
             - 3.4 million files
             - One timeline, finally

             ### What you asked for

             Most of what shipped this year came from your replies: the
             [timeline](/changelog/timeline-view), [faster search](/changelog/faster-search)
             and [exports](/changelog/exports). Keep them coming. We read every one.

             ---

             ## What comes next

             #### This winter

             - Calendar view
               - [x] Design
               - [ ] Beta
             - Offline notes
               - [ ] Design

             > When we started using Atelier, our Monday meeting got shorter.
             >
             > Then it stopped being about where things were, and started being about the work.

             Thank you for building it with us. It is a __small__ studio[^2] that makes it, and
             a **large** one that uses it.

             [^1]: Studios with at least one project active this month.
             [^2]: Seven people, in Porto and Osaka.
             """
           }}
        ]
      },
      %{
        slug: "calendar-view",
        categories: ["new"],
        segments: ["plan:pro", "role:owner"],
        hours: 72,
        shots: s,
        tables: %{"Monday" => :column},
        translations: [
          {"en",
           %{
             title: "Calendar view",
             summary: "Every due date of every project, on a month you can share.",
             body: """
             ![The calendar of October](attachment:calendar)

             In {purple|Beta} for the owners of Pro studios. Subscribe from
             `Calendar → Share`.

             | Monday | 4 tasks |
             | --- | --- |
             | Tuesday | 7 tasks |
             | Wednesday | 3 tasks |

             https://atelier.test/calendar
             """
           }}
        ]
      },
      %{
        slug: "offline-notes",
        categories: ["new"],
        shots: s,
        translations: [
          {"en",
           %{
             title: "Offline notes",
             summary: "Write notes on a train. They sync when you are back.",
             body: """
             A draft: notes that work with no connection, and sync when it comes back.
             """
           }}
        ]
      }
    ]
  end
end
