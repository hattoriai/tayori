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
