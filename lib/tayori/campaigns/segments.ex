defmodule Tayori.Campaigns.Segments do
  @moduledoc """
  The saved conditions on the app's people (`Tayori.Campaigns.Segment`):
  what the admin's Audience page does, for a script or a seed too.

      {:ok, segment} =
        Tayori.Campaigns.Segments.create(%{
          "name" => "Pro",
          "condition" => %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}
        })

  The condition is checked against the audience's attributes
  (`Tayori.Conditions.validate/3`). Each change is told on the PubSub as
  `{Tayori, :segment_changed, id}` (see `Tayori.subscribe/0`). A segment
  that a campaign names cannot be deleted.
  """

  import Ecto.Query

  alias Tayori.{Audience, Conditions, Config}
  alias Tayori.Campaigns.{Campaign, Segment, Step}

  @doc """
  The segments, by name. Options: `:counts` - with how many people each
  has now (`Segment.count`), one query each (`false`).
  """
  @spec list(keyword()) :: [Segment.t()]
  def list(opts \\ []) do
    config = Config.get()

    segments =
      from(s in Segment, order_by: [asc: s.name, asc: s.id])
      |> config.repo.all(prefix: config.prefix)

    if opts[:counts] do
      now = DateTime.utc_now()
      Enum.map(segments, &%{&1 | count: Audience.count(&1.condition, now)})
    else
      segments
    end
  end

  @doc "A segment by its id, or nil."
  @spec get(String.t()) :: Segment.t() | nil
  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        config = Config.get()
        config.repo.get(Segment, uuid, prefix: config.prefix)

      :error ->
        nil
    end
  end

  @doc "A changeset of a segment, for a form."
  @spec change(Segment.t(), map()) :: Ecto.Changeset.t()
  def change(%Segment{} = segment, attrs \\ %{}) do
    Segment.changeset(segment, attrs, Audience.attributes(audience!()))
  end

  @doc "Creates a segment: a name, a description, a condition."
  @spec create(map()) :: {:ok, Segment.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    config = Config.get()

    %Segment{}
    |> change(attrs)
    |> config.repo.insert(prefix: config.prefix)
    |> changed()
  end

  @doc "Updates a segment."
  @spec update(Segment.t(), map()) :: {:ok, Segment.t()} | {:error, Ecto.Changeset.t()}
  def update(%Segment{} = segment, attrs) do
    config = Config.get()

    segment
    |> change(attrs)
    |> config.repo.update(prefix: config.prefix)
    |> changed()
  end

  @doc """
  Deletes a segment, unless a campaign names it (its audience, its goal, a
  step's skip): then `{:error, {:in_use, names}}`, the campaigns' names.
  """
  @spec delete(Segment.t()) ::
          {:ok, Segment.t()} | {:error, {:in_use, [String.t()]}} | {:error, Ecto.Changeset.t()}
  def delete(%Segment{} = segment) do
    config = Config.get()

    case used_by(config, segment.id) do
      [] -> segment |> config.repo.delete(prefix: config.prefix) |> changed()
      names -> {:error, {:in_use, names}}
    end
  end

  @doc "The names of the campaigns that name a segment, by name."
  @spec used_by(String.t()) :: [String.t()]
  def used_by(id) when is_binary(id), do: used_by(Config.get(), id)

  # The conditions are maps in the database, read here: the campaigns are
  # few.
  defp used_by(config, id) do
    campaigns =
      from(c in Campaign, select: {c.id, c.name, c.audience, c.goal})
      |> config.repo.all(prefix: config.prefix)

    skips =
      from(s in Step, where: not is_nil(s.skip_if), select: {s.campaign_id, s.skip_if})
      |> config.repo.all(prefix: config.prefix)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    campaigns
    |> Enum.filter(fn {campaign_id, _name, audience, goal} ->
      conditions = [audience, goal | Map.get(skips, campaign_id, [])]
      Enum.any?(conditions, &(id in Conditions.segment_ids(&1)))
    end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort()
  end

  defp changed({:ok, segment}) do
    Tayori.broadcast({Tayori, :segment_changed, segment.id})
    {:ok, segment}
  end

  defp changed(error), do: error

  defp audience! do
    Audience.current() ||
      raise ArgumentError, "the :campaigns module is off: add it to the :modules of Tayori"
  end
end
