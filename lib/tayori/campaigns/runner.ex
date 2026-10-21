defmodule Tayori.Campaigns.Runner do
  @moduledoc false
  # Runs the campaigns: takes people into sequences, advances them, sends
  # the broadcasts.

  alias Tayori.Config

  @doc false
  # An event was tracked: the active sequences it triggers take the
  # person in. Step 2: enrolls them.
  @spec event_tracked(Config.t(), String.t(), String.t(), DateTime.t()) :: :ok
  def event_tracked(%Config{}, _person_id, _name, %DateTime{}), do: :ok
end
