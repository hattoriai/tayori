defmodule Tayori.Reader do
  @moduledoc ~S"""
  Who reads the news, as the app knows them. The app's resolver builds it
  from the app's own user (`c:Tayori.Resolver.resolve_reader/1`):

      %Tayori.Reader{
        id: "user:#{user.id}",
        segments: ["plan:#{user.plan}", "role:#{user.role}"],
        locale: user.locale,
        since: user.inserted_at
      }

    * `:id` - a stable key of the reader, where Tayori keeps when they
      last saw the news. Nil for a visitor: the news shows, nothing is
      unread.
    * `:segments` - what the reader is, in the words of the app. An entry
      for segments shows to readers in at least one of them.
    * `:locale` - the language to show the news in, when the entry has it.
    * `:since` - entries published before this time are never unread, so
      that a new account does not start with all the news of the past.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          segments: [String.t()],
          locale: String.t() | nil,
          since: DateTime.t() | nil
        }

  defstruct id: nil, segments: [], locale: nil, since: nil

  @doc """
  A visitor: no id, no segments. They see the entries for everyone.

  ## Examples

      iex> Tayori.Reader.visitor("pt-PT")
      %Tayori.Reader{id: nil, segments: [], locale: "pt-PT", since: nil}

  """
  @spec visitor(String.t() | nil) :: t()
  def visitor(locale \\ nil), do: %__MODULE__{locale: locale}
end
