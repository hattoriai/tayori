defmodule TayoriDev.CampaignSeeds do
  @moduledoc """
  Atelier's people and its campaigns, the first time the dev server
  starts with the campaigns: thirty people on three plans, some new this
  week, three segments, the welcome sequence (started, with the people
  of this week in it, whose first letters go to the mailbox at
  /dev/mailbox), a broadcast sent and a broadcast to write.
  """

  import Ecto.Query

  alias Tayori.Campaigns
  alias Tayori.Campaigns.Segments
  alias TayoriDev.{Person, Repo}

  @author %{"id" => 1, "name" => "Hattori Hanzo", "email" => "hanzo@atelier.test"}

  @names ~w(Ada Grace Noah Mei Tomás Inês Kofi Yuki Lena Omar Sofia Ravi Elif Jonas Amara
            Hugo Priya Mateo Nadia Felix Zara Kenji Lucía Ewan Chiara Idris Maren Dario
            Anouk Sami)
  @surnames ~w(Okafor Moreira Kim Tanaka Silva Haddad Novak Ferreira Lindqvist Mensah)

  def run do
    if Repo.aggregate(Person, :count) == 0 and Campaigns.list(archived: true) == [] do
      people()
      segments = segments()
      welcome(segments)
      broadcasts(segments)
    end

    :ok
  end

  defp people do
    now = DateTime.utc_now()

    for {first, i} <- Enum.with_index(@names) do
      surname = Enum.at(@surnames, rem(i * 7, length(@surnames)))
      plan = Enum.at(~w(free free pro studio free pro), rem(i, 6))
      days = if i < 8, do: rem(i, 6), else: 10 + i * 9

      %Person{
        name: "#{first} #{surname}",
        email: "#{String.downcase(first)}.#{String.downcase(surname)}@example.com",
        locale: if(rem(i, 4) == 1, do: "pt-PT", else: "en"),
        plan: plan,
        projects: if(i < 8, do: rem(i, 3), else: rem(i * 5, 11)),
        marketing: rem(i, 3) != 2,
        inserted_at: now |> DateTime.add(-days, :day) |> DateTime.add(-i * 3600)
      }
      |> Repo.insert!()
    end

    # What some of them did, as the app tells Tayori.
    for person <- Repo.all(from(p in Person, where: p.projects > 0)) do
      Tayori.track("person:#{person.id}", "project_created", at: person.inserted_at)
    end
  end

  defp segments do
    for {name, description, condition} <- [
          {"Paying", "On Pro or Studio.",
           %{"attribute" => "plan", "op" => "in", "value" => ["pro", "studio"]}},
          {"New this week", nil,
           %{"attribute" => "signed_up_at", "op" => "less_than_days_ago", "value" => 7}},
          {"No project yet", "Signed up, made nothing: they need a hand.",
           %{"all" => [%{"attribute" => "projects", "op" => "eq", "value" => 0}]}}
        ],
        into: %{} do
      {:ok, segment} =
        Segments.create(%{"name" => name, "description" => description, "condition" => condition})

      {name, segment}
    end
  end

  defp welcome(segments) do
    {:ok, welcome} =
      Campaigns.create(
        %{
          "name" => "Welcome to Atelier",
          "kind" => "sequence",
          "trigger" => %{"type" => "event", "event" => "signed_up"},
          "goal" => %{"attribute" => "projects", "op" => "gte", "value" => 3},
          "min_gap_hours" => 20,
          "max_days" => 21
        },
        author: @author
      )

    steps = [
      {0, nil,
       [
         {"en", "Welcome to Atelier, {{first_name|there}}",
          "Your studio has a home now.\n\nStart with **one project**: a client, a brief, a deadline. The rest follows.",
          "Open Atelier"},
         {"pt-PT", "Bem-vindo ao Atelier, {{first_name|olá}}",
          "O seu estúdio tem agora uma casa.\n\nComece com **um projeto**: um cliente, um briefing, um prazo.",
          "Abrir o Atelier"}
       ]},
      {2 * 1440, %{"attribute" => "projects", "op" => "gt", "value" => 0},
       [
         {"en", "Your first project, in two minutes",
          "A project is a board, its files and its people. Make one from a template, and change what you like.",
          "Make a project"}
       ]},
      {5 * 1440, %{"segment" => segments["Paying"].id, "op" => "in"},
       [
         {"en", "Atelier is better with your team",
          "Invite the people you work with: they see the boards, the files and the deadlines you share with them.",
          "Invite your team"}
       ]}
    ]

    for {wait, skip_if, letters} <- steps do
      {:ok, _step} =
        Campaigns.add_step(welcome, %{
          "wait" => wait,
          "skip_if" => skip_if,
          "letters" =>
            for {locale, subject, body, cta} <- letters do
              %{
                "locale" => locale,
                "subject" => subject,
                "body" => Kotoba.Content.from_markdown(body),
                "cta_label" => cta,
                "cta_url" => "{{dashboard_url}}"
              }
            end
        })
    end

    {:ok, welcome} = Campaigns.start(welcome)
    {:ok, _n} = Campaigns.enroll_segment(welcome, segments["New this week"])
  end

  defp broadcasts(segments) do
    {:ok, sent} =
      Campaigns.create(
        %{
          "name" => "Atelier 3.0",
          "kind" => "broadcast",
          "purpose" => "marketing",
          "audience" => %{"segment" => segments["Paying"].id, "op" => "in"}
        },
        author: @author
      )

    {:ok, _letter} =
      Campaigns.put_letter(hd(sent.steps), "en", %{
        "subject" => "Atelier 3.0: boards that plan themselves",
        "preheader" => "Timelines from your deadlines, and a calmer inbox.",
        "body" =>
          Kotoba.Content.from_markdown(
            "Hello {{first_name|there}},\n\nAtelier 3.0 is out. Your boards now draw their own timeline from the deadlines you set.\n\n- A timeline on every board\n- Files that follow their project\n- A quieter inbox"
          ),
        "cta_label" => "See what's new",
        "cta_url" => "http://localhost:#{System.get_env("PORT", "4099")}/changelog"
      })

    {:ok, _sent} = Campaigns.send_broadcast_now(Campaigns.get(sent.id))

    {:ok, draft} =
      Campaigns.create(
        %{
          "name" => "The spring studio report",
          "kind" => "broadcast",
          "purpose" => "marketing",
          "audience" => %{
            "all" => [
              %{"attribute" => "marketing", "op" => "true"},
              %{"attribute" => "projects", "op" => "gte", "value" => 2}
            ]
          }
        },
        author: @author
      )

    {:ok, _letter} =
      Campaigns.put_letter(hd(draft.steps), "en", %{
        "subject" => "How studios worked this spring",
        "body" =>
          Kotoba.Content.from_markdown(
            "Hi {{first_name|there}},\n\nWe looked at how the studios on Atelier planned their spring. Here is what we learned."
          )
      })
  end
end
