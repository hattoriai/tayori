defmodule TayoriTest.FakeAI do
  @moduledoc """
  The model of the tests: it streams the chunks the test gave it
  (`answer/1`), and tells the test what it was asked.

  With `answer(:writer)`, it writes what it is asked, the same way each
  time: a digest titled with its first change, summarised with their
  count and the language, its body a list of their titles; a
  translation with each part marked with its language (`[pt-PT] ...`).
  `answer({:writer, fail: locale})` fails the translation into a language.
  """
  @behaviour Tayori.AI

  def answer(chunks), do: :persistent_term.put({__MODULE__, :answer}, {self(), chunks})

  @impl true
  def stream(model, key, system, prompt) do
    {test, chunks} = :persistent_term.get({__MODULE__, :answer}, {nil, ["OK"]})
    if test, do: send(test, {:asked, %{model: model, key: key, system: system, prompt: prompt}})

    case chunks do
      {:error, reason} -> {:error, reason}
      :writer -> write(system, prompt, [])
      {:writer, opts} -> write(system, prompt, opts)
      chunks -> {:ok, chunks}
    end
  end

  defp write(system, prompt, opts) do
    locale =
      case Regex.run(~r/Write in\s.*?(?:\(([^)]+)\)|tag is (\S+?))\./s, system) do
        [_, locale] -> locale
        [_, "", locale] -> locale
      end

    cond do
      prompt =~ "Write one entry" ->
        [_, changes] = String.split(prompt, "The changes:\n\n", parts: 2)
        titles = for [_, title] <- Regex.scan(~r/^- (.+?)(?: \(.*\))?$/m, changes), do: title

        {:ok,
         [
           "TITLE: #{hd(titles)}\nSUMMARY: #{length(titles)} changes, in #{locale}.\n",
           "---\n",
           Enum.map_join(titles, "\n", &"- #{&1}")
         ]}

      locale == opts[:fail] ->
        {:error, :overloaded}

      prompt =~ "Translate this entry" ->
        [_, entry] = String.split(prompt, "The entry:\n\n", parts: 2)
        {:ok, %{title: title, summary: summary}, body} = Tayori.AI.parse_header(entry)

        {:ok,
         [
           "TITLE: [#{locale}] #{title}\nSUMMARY: [#{locale}] #{summary}\n---\n",
           "[#{locale}] " <> String.trim(body)
         ]}

      true ->
        {:ok, ["OK"]}
    end
  end
end

defmodule TayoriTest.Vault do
  @moduledoc """
  A vault with the functions of a Cloak.Vault, for the tests: a tag, and
  the text reversed and encoded.
  """

  def encrypt(plain), do: {:ok, "vault:" <> Base.encode64(String.reverse(plain))}

  def decrypt("vault:" <> encoded) do
    with {:ok, reversed} <- Base.decode64(encoded), do: {:ok, String.reverse(reversed)}
  end

  def decrypt(_other), do: {:error, :not_this_vault}
end
