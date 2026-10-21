defmodule Tayori.Locales do
  @moduledoc """
  The names of the languages of the entries, for the admin's tabs and the
  readers' language links.

  The entries can be written in any language, so Tayori names none: the
  app names them in the `:locales` option (`{"pt-PT", "Português"}`), and
  a language it does not name shows its tag.

  ## Examples

      iex> config =
      ...>   Tayori.Config.new(
      ...>     repo: MyApp.Repo,
      ...>     pubsub: MyApp.PubSub,
      ...>     locales: [{"en", "English"}, {"pt-PT", "Português"}, "tlh"]
      ...>   )
      iex> Tayori.Locales.name(config, "pt-PT")
      "Português"
      iex> Tayori.Locales.name(config, "tlh")
      "tlh"

  """

  alias Tayori.Config

  @doc "The name of a language, as the app's config names it."
  @spec name(String.t()) :: String.t()
  def name(locale), do: name(Config.get(), locale)

  @doc "The name of a language in `config`: the app's, else its tag."
  @spec name(Config.t(), String.t()) :: String.t()
  def name(%Config{locale_names: names}, locale), do: Map.get(names, locale, locale)
end
