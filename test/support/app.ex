defmodule TayoriTest.Person do
  @moduledoc "A person of the app of the tests."
  use Ecto.Schema

  schema "test_people" do
    field :name, :string
    field :email, :string
    field :locale, :string
    field :plan, :string
    field :visits, :integer
    field :born_on, :date
    field :closed_at, :utc_datetime_usec
    field :optional_emails, :boolean, default: true
    field :inserted_at, :utc_datetime_usec
    has_many :photos, TayoriTest.Photo
    has_many :stories, TayoriTest.Story
  end
end

defmodule TayoriTest.Photo do
  @moduledoc "A photo of a person of the app."
  use Ecto.Schema

  schema "test_photos" do
    belongs_to :person, TayoriTest.Person
  end
end

defmodule TayoriTest.Story do
  @moduledoc "A story of a person of the app, published or not."
  use Ecto.Schema

  schema "test_stories" do
    belongs_to :person, TayoriTest.Person
    field :published_at, :utc_datetime_usec
  end
end

defmodule TayoriTest.Audience do
  @moduledoc """
  The audience of the tests: the people of the app who have not closed
  their account, with every callback of `Tayori.Audience`.
  """
  @behaviour Tayori.Audience

  import Ecto.Query

  alias Tayori.Audience
  alias TayoriTest.{Person, Photo, Story}

  @impl true
  def query, do: from(p in Person, as: :person, where: is_nil(p.closed_at))

  @impl true
  def where_ids(query, ids) do
    ids =
      for "person:" <> id <- ids, {id, ""} <- [Integer.parse(id)], do: id

    where(query, [person: p], p.id in ^ids)
  end

  @impl true
  def recipient(%Person{} = person) do
    %Tayori.Recipient{
      id: "person:#{person.id}",
      email: person.email,
      name: person.name,
      locale: person.locale,
      since: person.inserted_at,
      data: %{
        "first_name" => person.name && person.name |> String.split() |> List.first(),
        "optional_emails" => person.optional_emails
      }
    }
  end

  @impl true
  def person_id, do: dynamic([person: p], fragment("'person:' || CAST(? AS TEXT)", p.id))

  @impl true
  def attributes do
    [
      Audience.attribute(:name, "Name", :string, dynamic([person: p], p.name)),
      Audience.attribute(:email, "Email", :string, dynamic([person: p], p.email)),
      Audience.attribute(
        :plan,
        "Plan",
        {:enum, [{"free", "Free"}, {"pro", "Pro"}, {"team", "Team"}]},
        dynamic([person: p], p.plan)
      ),
      Audience.attribute(:visits, "Visits", :integer, dynamic([person: p], p.visits)),
      Audience.attribute(:born_on, "Born", :date, dynamic([person: p], p.born_on)),
      Audience.attribute(
        :signed_up_at,
        "Signed up",
        :datetime,
        dynamic([person: p], p.inserted_at)
      ),
      Audience.attribute(
        :optional_emails,
        "Takes optional emails",
        :boolean,
        dynamic([person: p], p.optional_emails)
      ),
      Audience.attribute(
        :has_photos,
        "Has photos",
        :boolean,
        dynamic(
          [person: p],
          exists(from(ph in Photo, where: ph.person_id == parent_as(:person).id))
        )
      ),
      Audience.attribute(
        :has_story,
        "Has a story",
        :boolean,
        dynamic(
          [person: p],
          exists(from(s in Story, where: s.person_id == parent_as(:person).id))
        )
      ),
      Audience.attribute(
        :published,
        "Published a story",
        :boolean,
        dynamic(
          [person: p],
          exists(
            from(s in Story,
              where: s.person_id == parent_as(:person).id and not is_nil(s.published_at)
            )
          )
        )
      ),
      # A count, as a correlated scalar subquery.
      Audience.attribute(
        :photos,
        "Photos",
        :integer,
        dynamic(
          [person: p],
          subquery(
            from(ph in Photo, where: ph.person_id == parent_as(:person).id, select: count())
          )
        )
      )
    ]
  end

  @impl true
  def can_email?(%Tayori.Recipient{data: data}, :marketing), do: data["optional_emails"] == true
  def can_email?(_recipient, :product), do: true

  @impl true
  def events, do: [{"signed_up", "Signed up"}, {"story_published", "Published a story"}]

  @impl true
  def order(query), do: order_by(query, [person: p], asc: p.id)
end

defmodule TayoriTest.Provider do
  @moduledoc "A mail provider of the app's own, for the config's checks."
  def verify(_conn, _raw_body, _opts), do: :ok
  def events(_payload), do: []
end
