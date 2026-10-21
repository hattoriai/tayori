defmodule Tayori.Recipient do
  @moduledoc ~S"""
  A person of the app, as the campaigns write to them. The app's audience
  builds it from a row of its own query (`c:Tayori.Audience.recipient/1`):

      %Tayori.Recipient{
        id: "user:#{user.id}",
        email: user.email,
        name: user.name,
        locale: user.locale,
        since: user.inserted_at,
        data: %{"first_name" => user.first_name}
      }

    * `:id` - a stable key of the person, the one `Tayori.track/3` is
      given and `c:Tayori.Audience.where_ids/2` reads back.
    * `:email` - where the letters go. A person with no email is never
      written to.
    * `:name` - their name, on the letter's envelope.
    * `:locale` - the language of their letters, when the letter has it.
    * `:since` - when they became a person of the app.
    * `:data` - what else a letter may say of them, by key: a merge tag
      `{{first_name}}` is `data["first_name"]`.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t() | nil,
          name: String.t() | nil,
          locale: String.t() | nil,
          since: DateTime.t() | nil,
          data: map()
        }

  @enforce_keys [:id]
  defstruct [:id, :email, :name, :locale, :since, data: %{}]
end
