defmodule TayoriTest.FakeAI do
  @moduledoc """
  The model of the tests: it streams the chunks the test gave it
  (`answer/1`), and tells the test what it was asked.
  """
  @behaviour Tayori.AI

  def answer(chunks), do: :persistent_term.put({__MODULE__, :answer}, {self(), chunks})

  @impl true
  def stream(model, key, system, prompt) do
    {test, chunks} = :persistent_term.get({__MODULE__, :answer}, {nil, ["OK"]})
    if test, do: send(test, {:asked, %{model: model, key: key, system: system, prompt: prompt}})

    case chunks do
      {:error, reason} -> {:error, reason}
      chunks -> {:ok, chunks}
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
