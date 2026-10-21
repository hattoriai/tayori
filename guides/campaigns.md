# Campaigns

The changelog says the same news to everyone. The campaigns write to
each person, by what they did, at their own time: a welcome when they
sign up, a word two days later if they have not started, nothing once
they have. Two kinds:

* A **sequence**: a person enters on an event of your app (or by hand),
  then gets a series of letters, each at its time after they entered.
  A letter is left out when a condition says it is not wanted then. The
  person leaves at the sequence's goal, at its end, or when they cannot
  be emailed.
* A **broadcast**: one letter to everyone in an audience, now or at a
  time.

They are made of a few parts your app gives, or the admin writes:

* **the audience**: who your people are, and the facts Tayori may test
  of them, as Ecto queries on your own schemas (`Tayori.Audience`);
* **conditions**: rules on those facts and on events
  (`Tayori.Conditions`);
* **segments**: conditions saved with a name;
* **events**: what a person did, told by your app (`Tayori.track/3`);
* **the runner**: Oban jobs, or Tayori's scheduler without Oban.

Tayori copies nothing of your people. Each condition becomes SQL and
runs in your database, on PostgreSQL or SQLite. The letters go through
your Swoosh mailer.

## Turning it on

The campaigns are a module of their own. `:modules` says which Tayori
runs: `[:changelog]` (the default), `[:campaigns]`, or both. A module
that is off has no admin page, no route that answers, no MCP tool, no
process and no job.

```elixir
{Tayori,
 repo: MyApp.Repo,
 pubsub: MyApp.PubSub,
 oban: Oban,
 secret_key_base: Application.fetch_env!(:my_app, MyAppWeb.Endpoint)[:secret_key_base],
 mailer: MyApp.Mailer,
 modules: [:changelog, :campaigns],
 campaigns: [
   audience: MyApp.TayoriAudience,
   url: "https://atelier.app/letters",
   from: {"Rui at Atelier", "rui@atelier.app"},
   reply_to: "rui@atelier.app",
   providers: [resend: [secret: "whsec_..."]]
 ]}
```

The options of `:campaigns`:

* `:audience` - your `Tayori.Audience` (required).
* `:url` - where `tayori_mail` is mounted, for the links of the letters
  (required).
* `:from` - who the letters are from, `{"Name", "address"}` or an
  address; `:email_from` when not given. One is required.
* `:reply_to` - where replies go. Optional.
* `:providers` - your mail provider's webhooks, for bounces and
  complaints (see [Providers](#providers)). Optional.
* `:keep_events_days` - how long the events are kept (400).

The module also needs `:mailer` and `:secret_key_base` (it signs the
links to unsubscribe), and Swoosh in your deps. `Tayori.Config` refuses
to start without them, and says what is missing.

The tables are in Tayori's migration, version 2: every table is made
whatever the modules, so turning the campaigns on needs no migration
once your app is on version 2. An app on version 1 runs
`mix tayori.gen.migration`, which writes the one that upgrades:

```elixir
defmodule MyApp.Repo.Migrations.UpgradeTayori do
  use Ecto.Migration
  def up, do: Tayori.Migrations.up(version: 2)
  def down, do: Tayori.Migrations.down(to: 1)
end
```

### The mount

Each letter links to a page to unsubscribe, and your mail provider
posts its webhooks. Both are `tayori_mail`, at the `:url` of
`:campaigns`:

```elixir
import Tayori.Router

pipeline :letters do
  plug :accepts, ["html", "json"]
end

scope "/" do
  pipe_through :letters
  tayori_mail "/letters"
end
```

The pipeline has no session and no `:protect_from_forgery`: a mail
client's one-click unsubscribe and a provider's webhook carry no CSRF
token. Each request proves itself instead: the link's token is signed,
and the webhook is signed or authenticated. The webhook's signature is
of the body as it was sent; when your endpoint's `Plug.Parsers` reads
JSON before the router, give it Tayori's body reader:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  json_decoder: JSON,
  body_reader: {Tayori.RawBody, :read_body, []}
```

### Oban

With Oban (the `:oban` option), each person in a sequence has one job,
at the time of their next step, moved when it moves; a broadcast has a
job at its time, tried again from where it stopped when it fails; each
letter is a job, tried five times before it is "failed". A sweep, one
job in the cluster at boot and then every hour, gives a job to what lost
its own: a person more than 5 minutes past their time, a broadcast more
than 5 minutes past its time or sending with no batch in 5 minutes, a
letter queued for more than 15 minutes (but those of a paused
sequence). A letter is claimed before it goes, so that one with two jobs
goes once. Start Tayori after Oban.

Without Oban, the scheduler looks each minute, and when a write makes
something due sooner, at what is due: the people whose time came, 200
at a time, the broadcasts, and a broadcast a stopped node or an error
left half sent (no one gets it twice). The letters go from a task, one
after the other, tried once; one that fails is "failed", and logged. A
node stopped while it sends loses the letters it had not sent: no one
gets a letter twice, but some may not get it. Run Oban when the letters
matter.

## The audience

Your app says who its people are, and what Tayori may know of them, in
one module:

```elixir
defmodule MyApp.TayoriAudience do
  @behaviour Tayori.Audience
  import Ecto.Query

  alias MyApp.Accounts.User
  alias MyApp.Projects.{Invoice, Project}

  # Your people: an Ecto query with the binding :person.
  @impl true
  def query, do: from(u in User, as: :person, where: is_nil(u.deleted_at))

  # The query narrowed to some of them, by the ids recipient/1 gives.
  @impl true
  def where_ids(query, ids) do
    ids = for "user:" <> id <- ids, {id, ""} <- [Integer.parse(id)], do: id
    where(query, [person: u], u.id in ^ids)
  end

  # A row, as a person to write to.
  @impl true
  def recipient(%User{} = u) do
    %Tayori.Recipient{
      id: "user:#{u.id}",
      email: u.email,
      name: u.name,
      locale: u.locale,
      since: u.inserted_at,
      data: %{
        "first_name" => u.first_name,
        "dashboard_url" => "https://atelier.app/dashboard",
        "marketing" => u.marketing_opt_in
      }
    }
  end

  # The same id, as SQL: conditions on events need it.
  @impl true
  def person_id, do: dynamic([person: u], fragment("'user:' || CAST(? AS TEXT)", u.id))

  # The facts conditions may test.
  @impl true
  def attributes do
    [
      Tayori.Audience.attribute(
        :plan,
        "Plan",
        {:enum, [{"free", "Free"}, {"pro", "Pro"}, {"team", "Team"}]},
        dynamic([person: u], u.plan)
      ),
      Tayori.Audience.attribute(:signed_up_at, "Signed up", :datetime,
        dynamic([person: u], u.inserted_at)
      ),
      Tayori.Audience.attribute(:company, "Company", :string, dynamic([person: u], u.company)),
      # Whether something exists: a boolean.
      Tayori.Audience.attribute(:has_projects, "Has a project", :boolean,
        dynamic(
          [person: u],
          exists(from(p in Project, where: p.owner_id == parent_as(:person).id))
        )
      ),
      # How many: an integer, a scalar subquery.
      Tayori.Audience.attribute(:projects, "Projects", :integer,
        dynamic(
          [person: u],
          subquery(
            from(p in Project, where: p.owner_id == parent_as(:person).id, select: count())
          )
        ),
        description: "The projects they own."
      ),
      Tayori.Audience.attribute(:paid, "Has paid", :boolean,
        dynamic(
          [person: u],
          exists(from(i in Invoice, where: i.user_id == parent_as(:person).id and i.paid))
        )
      )
    ]
  end

  # Their consent, as your app keeps it.
  @impl true
  def can_email?(%Tayori.Recipient{data: data}, :marketing), do: data["marketing"] == true
  def can_email?(_recipient, :product), do: true

  # The events the admin offers (any name may be tracked anyway).
  @impl true
  def events, do: [{"signed_up", "Signed up"}, {"project_created", "Created a project"}]
end
```

The callbacks:

* `query/0` - your people, with the binding `:person` (required).
* `where_ids/2` - the query narrowed to these ids (required).
* `recipient/1` - a row of the query as a `Tayori.Recipient`: its `id`,
  `email`, `name`, `locale`, `since` and `data`, the values of the
  letters' merge tags (required). A person with no email is never
  written to: their letter is "skipped", `no_email`.
* `attributes/0` - the facts conditions test, each made with
  `Tayori.Audience.attribute/5`. Without it, conditions test events and
  segments only.
* `person_id/0` - the recipient's id as SQL. Without it, conditions on
  events are refused.
* `can_email?/2` - whether a person may get a letter of a purpose,
  `:product` or `:marketing`. Without it, everyone may.
* `events/0` - the events the admin offers.
* `key/0` - what people are read by, for batches: a `dynamic` on
  `:person` that is unique to each person and sortable, such as
  `dynamic([person: u], u.id)`; the binding's `id` without it. Each
  batch starts after the last key of the one before, so that people
  who join or leave while a broadcast goes move no one else. Your
  `query/0` may select a row of its own: `recipient/1` gets that row.

An attribute's type is `:string`, `:integer`, `:boolean`, `:datetime`
(UTC), `:date`, or `{:enum, [{value, label}]}`. Its expression is a
`dynamic` on `:person`: a column, a join's column, a subquery. It runs
in your database, as part of the query of each condition.

The audience's functions answer for the running Tayori, and take a
condition (nil is everyone): `Tayori.Audience.count/2`, `sample/3`,
`each_batch/4`, `get/1`, `match?/3`.

## Conditions

A condition is data, a map with string keys, kept as it is:

```elixir
%{"all" => [
  %{"attribute" => "plan", "op" => "in", "value" => ["pro", "team"]},
  %{"attribute" => "signed_up_at", "op" => "more_than_days_ago", "value" => 7},
  %{"not" => %{"attribute" => "has_projects", "op" => "true"}},
  %{"event" => "project_created", "op" => "not_happened", "within_days" => 30},
  %{"segment" => "<segment id>", "op" => "in"}
]}
```

Groups are `all`, `any` and `not`. `%{"all" => []}` (or nil) is
everyone, `%{"any" => []}` no one. The operators, by type:

| Type | Operators | Value |
|---|---|---|
| string | `eq`, `neq`, `contains`, `starts_with`, `set`, `not_set` | a string |
| integer | `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `set`, `not_set` | an integer |
| boolean | `true`, `false` | none |
| datetime, date | `before`, `after` | an ISO 8601 date or time |
| | `more_than_days_ago`, `less_than_days_ago` | a positive number of days |
| | `set`, `not_set` | none |
| enum | `in`, `not_in` | a list of the enum's values |
| event | `happened`, `not_happened` | `within_days`, optional |
| segment | `in`, `not_in` | the segment's id |

How they run:

* `Tayori.Conditions.compile/4` makes a condition an Ecto `dynamic` on
  `:person`, which Tayori puts in a `where` of your audience's query.
  The same condition gives the same people on PostgreSQL and SQLite.
* Strings are compared without case. `contains` and `starts_with` take
  the value as text: `%` and `_` are only themselves.
* A person with no value matches no comparison, and matches `neq` and
  `not_in`: "Plan is not Pro" is everyone but the Pro.
* Times are computed in Elixir, then compared as parameters. A date
  "after" is after that whole day.
* An event is a row of `tayori_events` with the person's id
  (`person_id/0`), ever or in the last `within_days`.
* A segment is its condition, inlined. One that leads back to itself is
  refused.
* An attribute your app no longer gives, or a deleted segment, matches
  no one, and Tayori logs it once.

`Tayori.Conditions.validate/3` checks a condition against your
attributes and says what is wrong in words: an unknown attribute, an
operator of another type, a bad value, a segment that does not exist.
`Tayori.Conditions.describe/2` says it as a sentence: "Plan is Pro and
signed up more than 7 days ago". A condition is at most 5 groups deep,
with 50 rules at most; the admin builds them 3 deep.

## Segments

A segment is a condition saved with a name and a description, for
campaigns, skips, goals and other segments to use. The admin makes them
at Audience → New segment, with a live count and the first people;
`Tayori.Campaigns.Segments` does it in code. A segment is not deleted
while a campaign uses it: the admin names what does.

```elixir
{:ok, pro} =
  Tayori.Campaigns.Segments.create(%{
    "name" => "Pro without a project",
    "condition" => %{"all" => [
      %{"attribute" => "plan", "op" => "in", "value" => ["pro"]},
      %{"attribute" => "has_projects", "op" => "false"}
    ]}
  })
```

## Events

Your app tells Tayori what a person did:

```elixir
Tayori.track("user:#{user.id}", "signed_up")
Tayori.track("user:#{user.id}", "project_created", meta: %{"project" => project.id})
Tayori.track("user:#{user.id}", "signed_up", at: user.inserted_at)
```

The id is the one `recipient/1` gives. The name is 64 characters at
most. An event is kept (`tayori_events`), for conditions to test, and
each active sequence whose trigger is that event takes the person in.
Without the campaigns module, `track/3` does nothing.

Events are kept 400 days (`keep_events_days`); a daily job deletes the
older ones.

## Sequences

A sequence has:

* **a trigger**: an event (`signed_up`), or by hand. By hand, people
  enter from the admin (all of a segment at once), from your code
  (`Tayori.Campaigns.enroll/3`, `enroll_segment/3`), or from the MCP
  (`enroll_people`).
* **who may enter**: a condition. Only those who match it when they
  would enter, enter. No condition: everyone.
* **steps**: each a letter, at a wait after the person entered (0 is at
  once; two steps cannot have the same wait), with an optional
  **skip_if**: a condition that, when it matches the person at the
  step's time, leaves the letter out.
* **a goal**, optional: a condition. Once it matches, the person leaves
  the sequence, done.
* **a gap**: the hours at least between two of its letters (24). A step
  whose time comes sooner waits for the gap; it is not left out.
* **max days**, optional: after them, the person leaves.
* **a purpose**: `product` (what the product needs to say) or
  `marketing` (news and offers). It decides what unsubscribing means,
  and is given to `can_email?/2`.

Each time a person's moment comes, the runner, in this order:

1. leaves them as they are if the sequence is paused;
2. ends their place if they are no longer one of your people ("left");
3. ends it at the goal ("goal");
4. ends it after `max_days` ("expired");
5. ends it if they unsubscribed from the purpose ("unsubscribed"), or
   `can_email?/2` says no ("cannot_email"): a person who cannot be
   emailed leaves the sequence, and does not come back to it;
6. takes the next step after where they are: not yet its time, it
   waits; its skip matches, it is left out (a delivery "skipped") and
   the next is judged; the gap is not over, it waits; otherwise the
   letter goes, once.

A step is judged when the person reaches it. A step whose moment passed
and is not wanted then is left out, and the person goes on: with a skip
"has a story", a person who wrote a story on day 3 never gets the day 4
letter about writing one. When nothing is left, they are done
("finished").

Editing a running sequence: the steps are read live. A step changed,
added or removed counts for everyone still before it. A step added at
or before where a person is goes to those who come after, not to them.
A step removed while its letter waits to go is not sent ("skipped",
`step_removed`). Once a sequence is started, each of its steps keeps its
letter in your first language whole: a step is added with it, in the
same call, and an edit that would leave it without a subject or a body
is refused (`{:error, :incomplete_letter}`). A step with no letter all
the same (made by hand) is left out (`no_letter`).

The steps go in the order of their waits. Before anyone enters, a step
moves up or down (`move_step/2`), trading times with its neighbour; once
someone has, a person is where the last step they had put them, and a
step moved before it would never reach them: moving is refused
(`{:error, :has_people}`), and the admin hides the arrows. Change the
times of the steps instead.

Its life: a draft, then **started** (it needs a step, and each step a
subject and a body in your first language), **paused** (no one enters,
and no letter goes, not even those queued before the pause; the people
wait), **resumed** (each goes on: at once for those whose time came
while it was paused, else at their time, and the letters queued go), and
**archived** (no one enters, those in it leave, "stopped", and their
letters not sent yet are skipped, `stopped`; it does not start again).

Each change of status is from the status the campaign had when it was
read: when another admin, or the sender, changed it meanwhile, nothing
changes and the call is `{:error, :stale}` (the admin says so and shows
the campaign as it is).

A person enters a sequence once, ever: signing up twice, or being taken
in by hand again, changes nothing.

```elixir
{:ok, tips} =
  Tayori.Campaigns.create(%{
    "name" => "Pro tips",
    "kind" => "sequence",
    "purpose" => "product",
    "trigger" => %{"type" => "manual"},
    "audience" => %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}
  })

{:ok, _step} = Tayori.Campaigns.add_step(tips, %{"wait" => 0, "letters" => [...]})
{:ok, tips} = Tayori.Campaigns.start(tips)

{:ok, _enrollment} = Tayori.Campaigns.enroll(tips, "user:42")
{:ok, 18} = Tayori.Campaigns.count_enrollable(tips, pro_segment)
{:ok, 18} = Tayori.Campaigns.enroll_segment(tips, pro_segment)
```

## Broadcasts

A broadcast is one letter to everyone in its audience, a saved segment
or a condition. It is read when it goes: those who match then get it,
less those who unsubscribed, bounced or may not be emailed. 500 people
are read at a time; each gets the letter once.

```elixir
{:ok, spring} =
  Tayori.Campaigns.create(%{
    "name" => "Spring",
    "kind" => "broadcast",
    "purpose" => "marketing",
    "audience" => %{"segment" => pro.id, "op" => "in"}
  })

[step] = spring.steps
{:ok, _letter} = Tayori.Campaigns.put_letter(step, "en", %{"subject" => "...", "body" => body})

{:ok, _} = Tayori.Campaigns.schedule_broadcast(spring, ~U[2026-11-02 09:00:00Z])
# or
{:ok, _} = Tayori.Campaigns.send_broadcast_now(spring)
```

A scheduled broadcast can be cancelled until it goes
(`cancel_broadcast/1`). A sent one stays as it went.

## Letters

A step has a letter in each of your languages (`:locales`), the first
required: a subject, a preheader (the line a mail client shows after the
subject), a body in Kotoba's editor (headings, lists, links, quotes,
images), and an optional button, a label and an `https` address. A
person gets the letter of their `locale`, else one of their language,
else your first language's.

The letter is an email in the look of Tayori's emails, from the
campaign's sender (`from` of `:campaigns`, or the campaign's own name
before the same address), with `reply_to`. Its links are made absolute
against the `:url` of `:campaigns`. It has a text part too.

**Merge tags** name what the letter knows of the person: `{{name}}`,
`{{email}}`, and any key of the recipient's `data`
(`{{first_name}}`, `{{dashboard_url}}`). A fallback is written after a
bar, for a person who has none: `{{first_name|there}}`. A tag with no
value and no fallback is left empty. Tags are replaced in the subject,
the preheader, the body, its links and the button; in the HTML their
values are escaped. A tag at the start of a link must be an address
(`https:`, `http:`, `mailto:`), else the link loses it; a tag after the
start is encoded as a part of the address. The admin's preview warns of
the tags a person lacks.

## Consent and unsubscribing

Two purposes: `product` and `marketing`. Each letter has a link to
unsubscribe from its purpose, in its footer and in its headers
(`List-Unsubscribe`, with `List-Unsubscribe-Post:
List-Unsubscribe=One-Click`, so that a mail client unsubscribes in one
click). The page, in the person's language, offers to unsubscribe from
everything too. A person who unsubscribed from marketing still gets the
product's letters.

What does not go:

* an address that unsubscribed, bounced hard or complained: a
  **suppression**, kept by address and purpose (`"all"`, `"marketing"`,
  `"product"`). An opt-out is final: Tayori never takes one back by
  itself. `Tayori.Campaigns.unsuppress/2` does, for an app that knows
  why;
* a person your `can_email?/2` says no for: your app's own consent, an
  account closed, deletion asked;
* a person with no email.

Each letter checks them again when it goes. A person in a sequence who
can no longer be emailed leaves it.

Your app can suppress an address itself: for a provider whose webhooks
it takes, or an address a person asked you to forget.

```elixir
:ok = Tayori.Campaigns.suppress("ada@example.com", "all", "manual")
Tayori.Campaigns.suppressed?("ada@example.com", :marketing)
#=> true
```

## Providers

Your mail provider tells of bounces and complaints by webhook, at
`{url}/webhooks/{name}`. A hard bounce or a complaint suppresses the
address for everything, and marks its letter "bounced" or "complained";
a delivery changes nothing; a soft bounce is nothing. The same event
twice is the same. Settings in the admin gives the webhooks' addresses
to paste.

Two are built in:

* **Resend**: `providers: [resend: [secret: "whsec_..."]]`, the signing
  secret of the webhook. Svix's signature is checked, and a request
  older than five minutes refused. Events `email.delivered`,
  `email.bounced`, `email.complained`.
* **Postmark**: `providers: [postmark: [username: "tayori", password:
  "..."]]`, the basic authentication you give Postmark in the webhook's
  address (`https://tayori:...@atelier.app/letters/webhooks/postmark`).
  Events `Delivery`, `Bounce` (hard for `HardBounce`) and
  `SpamComplaint`.

For another, write an adapter of `Tayori.Campaigns.Provider`: `verify/3`
says whether the request is the provider's, and `events/1` turns its
payload into Tayori's events. The route, the raw body, what each event
does and the tests' helper are Tayori's. Amazon SES, through an SNS
topic that posts to `https://atelier.app/letters/webhooks/ses?token=...`:

```elixir
defmodule MyApp.TayoriSES do
  @moduledoc "Amazon SES's bounces and complaints, from an SNS topic."
  @behaviour Tayori.Campaigns.Provider

  # The token in the topic's address, and the topic itself.
  @impl true
  def verify(conn, raw_body, %{token: token, topic_arn: topic_arn}) do
    given = URI.decode_query(conn.query_string)["token"] || ""

    with true <- Plug.Crypto.secure_compare(given, token),
         {:ok, %{"TopicArn" => ^topic_arn}} <- JSON.decode(raw_body) do
      :ok
    else
      _ -> :error
    end
  end

  # SNS asks once whether this address wants the topic's messages.
  @impl true
  def events(%{"Type" => "SubscriptionConfirmation", "SubscribeURL" => url}) do
    Req.get!(url)
    []
  end

  def events(%{"Type" => "Notification", "Message" => message}) do
    case JSON.decode(message) do
      {:ok, %{"notificationType" => type, "mail" => %{"messageId" => id}} = n} -> ses(type, n, id)
      _ -> []
    end
  end

  def events(_payload), do: []

  defp ses("Bounce", %{"bounce" => bounce}, id) do
    for %{"emailAddress" => email} <- bounce["bouncedRecipients"] || [],
        do: %{type: :bounced, email: email, provider_id: id, hard?: bounce["bounceType"] == "Permanent"}
  end

  defp ses("Complaint", %{"complaint" => complaint}, id) do
    for %{"emailAddress" => email} <- complaint["complainedRecipients"] || [],
        do: %{type: :complained, email: email, provider_id: id, hard?: true}
  end

  defp ses("Delivery", %{"delivery" => delivery}, id) do
    for email <- delivery["recipients"] || [],
        do: %{type: :delivered, email: email, provider_id: id, hard?: false}
  end

  defp ses(_type, _notification, _id), do: []
end
```

```elixir
providers: [ses: {MyApp.TayoriSES, token: System.fetch_env!("SES_WEBHOOK_TOKEN"), topic_arn: "arn:aws:sns:..."}]
```

`provider_id` is the id your mailer gave the email (Swoosh's adapters
return it, `{:ok, %{id: id}}`), which Tayori keeps with the letter. SNS
also signs each message with a certificate; check that too where a
token in the address is not enough.

## Results

Each campaign counts what it did (`Tayori.Campaigns.results/1`, and the
admin's Results card):

* a sequence: who entered, who is in it now, who reached the goal (and
  the share), who left and why; for each step, the letters sent,
  skipped, failed and bounced, and how many reached the goal after its
  letter (their last letter was this one);
* a broadcast: its recipients, and the letters sent, failed, bounced
  and complained of.

Tayori tracks no opens and no clicks.

## The admin

With the campaigns on, the admin has **Campaigns** and **Audience**
(and with the changelog off, only those and Settings).

* **Audience**: the attributes and events your app declares, and the
  segments with their counts. A segment's page has the condition
  builder: groups ("All of", "Any of"), rules by type, events,
  segments, three deep, with its sentence, its count and the first ten
  people as you change it.
* **Campaigns**: sequences and broadcasts, each with its numbers. A
  campaign's page has its settings, its steps from top to bottom (one
  open at a time, each with its wait, its skip and its letter in each
  language), the preview (a person of the audience, the letter as they
  get it, the tags they lack, a test to an address, prefilled from your
  resolver's `author/1` `"email"`), and its life: start, pause, resume,
  archive, take people in; schedule, send now, cancel. Before it sends
  or takes people in, it says how many.
* **Settings**: the modules on, and the providers' webhook addresses.

A read-only admin sees all of it and changes nothing.

## MCP

`Tayori.MCP` gives an agent the campaigns' tools: it reads the audience,
tries and saves segments, writes campaigns and their letters, previews
them, sends you a test, and starts, takes people in or sends only when
you ask, after saying how many it reaches. See the [MCP](mcp.md) guide.

## Testing

`Tayori.Test` runs the campaigns in the test's process, at a time of the
test's own, and the letters go through your mailer at once, with or
without Oban:

```elixir
import Swoosh.TestAssertions
import Tayori.Test

test "the welcome, then the tips two days later" do
  user = user_fixture()
  now = DateTime.utc_now()

  track!("user:#{user.id}", "signed_up", at: now)
  run_campaigns!(now)
  assert_email_sent(subject: "Welcome to Atelier")

  run_campaigns!(DateTime.add(now, 2, :day))
  assert_email_sent(subject: "Your first project")
end
```

* `track!/3` - an event, as `Tayori.track/3`.
* `run_campaigns!/2` - what is due at a time: the people whose moment
  came, and the broadcasts.
* `post_webhook!/2` - a provider's payload, as if it had posted it,
  without its signature.

Start Tayori with `scheduler: false` in your tests, so that nothing runs
by itself beside them.

## Limits

* A person enters a sequence once. There is no re-entry, and no entry
  on joining a segment.
* Steps are judged when a person reaches them, from where they are: a
  step added before that point does not go to them.
* No branches, no waits for an event, no actions but letters.
* No click or open tracking, no quiet hours, no time zones per person,
  no cap of letters across campaigns: the gap is per sequence.
* The runner reads 200 people at a time, a broadcast 500.
* A step does not move once someone has entered its sequence.

See [Known limits](limits.md) for the rest, SQLite included.

## The onboarding letters, whole

A photography site's first days: a welcome at sign-up, then a word on
the second day if they have no photograph and no story, on the fourth
if they have no story, on the sixth about layouts if they have one, on
the ninth about publishing; once each, one at most every 40 hours,
within the first 14 days, and none once a story is published, the site
is closed, or its owner turned the optional emails off.

A person here is a site, written to its owner. The audience:

```elixir
defmodule MyApp.TayoriAudience do
  @behaviour Tayori.Audience
  import Ecto.Query

  alias MyApp.{Photo, Site, Story}

  @impl true
  def query do
    from(s in Site,
      as: :person,
      join: o in assoc(s, :owner),
      as: :owner,
      where: is_nil(s.closed_at),
      preload: [owner: o]
    )
  end

  @impl true
  def where_ids(query, ids) do
    ids = for "site:" <> id <- ids, do: id
    where(query, [person: s], s.id in ^ids)
  end

  @impl true
  def recipient(%Site{owner: owner} = site) do
    %Tayori.Recipient{
      id: "site:#{site.id}",
      email: owner.email,
      name: owner.name,
      locale: site.language,
      since: site.inserted_at,
      data: %{
        "first_name" => owner.first_name,
        "darkroom_url" => "https://#{site.handle}.example.com/",
        "optional_emails" => owner.email_updates and is_nil(owner.deletion_asked_at)
      }
    }
  end

  @impl true
  def person_id, do: dynamic([person: s], fragment("'site:' || CAST(? AS TEXT)", s.id))

  @impl true
  def attributes do
    [
      Tayori.Audience.attribute(:has_photos, "Has photographs", :boolean,
        dynamic([person: s], exists(from(p in Photo, where: p.site_id == parent_as(:person).id)))
      ),
      Tayori.Audience.attribute(:has_story, "Has a story", :boolean,
        dynamic([person: s], exists(from(t in Story, where: t.site_id == parent_as(:person).id)))
      ),
      Tayori.Audience.attribute(:published, "Published a story", :boolean,
        dynamic(
          [person: s],
          exists(
            from(t in Story,
              where: t.site_id == parent_as(:person).id and not is_nil(t.published_at)
            )
          )
        )
      )
    ]
  end

  # The onboarding letters are optional: the owner's say.
  @impl true
  def can_email?(%Tayori.Recipient{data: data}, :marketing), do: data["optional_emails"] == true
  def can_email?(_recipient, :product), do: true

  @impl true
  def events, do: [{"signed_up", "Signed up"}]
end
```

The sequence, from a seed or a release task (or written in the admin):

```elixir
defmodule MyApp.Onboarding do
  @day 1440

  def create! do
    has = &%{"attribute" => &1, "op" => "true"}

    {:ok, onboarding} =
      Tayori.Campaigns.create(%{
        "name" => "Onboarding",
        "kind" => "sequence",
        "purpose" => "marketing",
        "trigger" => %{"type" => "event", "event" => "signed_up"},
        "goal" => has.("published"),
        "min_gap_hours" => 40,
        "max_days" => 14
      })

    steps = [
      {0, "Welcome to the darkroom", nil},
      {2 * @day, "Start with one series", %{"any" => [has.("has_photos"), has.("has_story")]}},
      {4 * @day, "A cover and a title", has.("has_story")},
      {6 * @day, "Try another layout", %{"not" => has.("has_story")}},
      {9 * @day, "Publish your first story", nil}
    ]

    for {wait, subject, skip_if} <- steps do
      {:ok, _step} =
        Tayori.Campaigns.add_step(onboarding, %{
          "wait" => wait,
          "skip_if" => skip_if,
          "letters" => [
            %{
              "locale" => "en",
              "subject" => subject,
              "body" => Kotoba.Content.from_markdown(File.read!("priv/letters/#{wait}.md")),
              "cta_label" => "Open the darkroom",
              "cta_url" => "{{darkroom_url}}"
            }
          ]
        })
    end

    {:ok, _} = Tayori.Campaigns.start(onboarding)
  end
end
```

At sign-up, the app tracks it:

```elixir
def create_site(attrs) do
  with {:ok, site} <- Repo.insert(Site.changeset(%Site{}, attrs)) do
    Tayori.track("site:#{site.id}", "signed_up")
    {:ok, site}
  end
end
```

And how it reads in each case:

| The site | Its letters |
|---|---|
| does nothing | welcome, day 2, day 4, day 9; not day 6 (no story) |
| adds photographs on day 1 | welcome, day 4, day 9 |
| writes a story on day 3 | welcome, day 6, day 9 |
| writes and publishes a story on day 1 | welcome only: the goal |
| is closed on day 1 | welcome only: it left |
| turned the optional emails off | none |
| is seen first on day 10 | the welcome, then each due letter 40 hours apart, until day 14 |

The test, as Tayori's own suite has it
(`test/tayori/campaigns/onboarding_test.exs`):

```elixir
test "a story, so neither the series nor the cover" do
  site = site_fixture()
  track!("site:#{site.id}", "signed_up", at: t0)

  run_campaigns!(t0)
  assert_email_sent(subject: "Welcome to the darkroom")
  story_fixture(site)

  run_campaigns!(DateTime.add(t0, 5, :day))
  assert_no_email_sent()

  run_campaigns!(DateTime.add(t0, 6, :day))
  assert_email_sent(subject: "Try another layout")
end
```
