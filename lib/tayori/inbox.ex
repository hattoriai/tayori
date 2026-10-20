defmodule Tayori.Inbox do
  @moduledoc """
  The changes that shipped, before they become entries: what the app's
  sources bring (`Tayori.Source`), what its CI, GitHub and its own code
  add, what an agent adds over MCP. The admin reads them in the inbox,
  puts aside what readers need not know, and a digest makes an entry of
  the rest (`Tayori.Digest`).

  A change is the source's and its ref's: adding it again changes
  nothing, so a source can give all it has each time it is read.

      Tayori.Inbox.add(%{ref: "pr-1234", title: "Exports in two clicks", kind: "added"},
        source: "app"
      )

  A change that does not say its audience takes the `:inbox` config's
  (`"public"`); one that does not say its category takes its kind's
  (the config's `:kinds`, or the category whose key is the kind).
  """

  import Ecto.Query

  alias Tayori.{Categories, Change, Config, Source}

  require Logger

  @doc """
  Adds a change, or finds the one with the same source and ref. Options:
  `:source` (`"app"`). Returns `{:ok, change}`, or `{:error, changeset}`.
  """
  @spec add(map(), keyword()) :: {:ok, Change.t()} | {:error, Ecto.Changeset.t()}
  def add(attrs, opts \\ []) when is_map(attrs) do
    case put(attrs, opts) do
      {:ok, change, _new_or_existing} -> {:ok, change}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # The change, and whether it was new.
  defp put(attrs, opts) do
    config = Config.get()

    case prepare(attrs, opts, config) do
      %Ecto.Changeset{valid?: true} = changeset ->
        source = Ecto.Changeset.get_field(changeset, :source)
        ref = Ecto.Changeset.get_field(changeset, :ref)

        case existing(config, source, ref) do
          %Change{} = change -> {:ok, change, :existing}
          nil -> insert(config, changeset, source, ref)
        end

      changeset ->
        {:error, changeset}
    end
  end

  defp insert(config, changeset, source, ref) do
    case config.repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:source, :ref],
           prefix: config.prefix
         ) do
      # Added by another at the same time: theirs is the change.
      {:ok, %Change{id: nil}} ->
        {:ok, existing(config, source, ref), :existing}

      {:ok, change} ->
        Tayori.broadcast({Tayori, :inbox, change.id})
        {:ok, change, :new}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp existing(config, source, ref) do
    config.repo.get_by(Change, [source: source, ref: ref], prefix: config.prefix)
  end

  @doc """
  Adds changes, each as `add/2` would. Returns how many were new, how
  many were there already, and the errors of those that could not be
  added, `{index, changeset}`.
  """
  @spec add_many([map()], keyword()) :: %{
          added: non_neg_integer(),
          existing: non_neg_integer(),
          errors: [{non_neg_integer(), Ecto.Changeset.t()}]
        }
  def add_many(changes, opts \\ []) when is_list(changes) do
    changes
    |> Enum.with_index()
    |> Enum.reduce(%{added: 0, existing: 0, errors: []}, fn {attrs, index}, acc ->
      case put(attrs, opts) do
        {:ok, _change, :new} -> %{acc | added: acc.added + 1}
        {:ok, _change, :existing} -> %{acc | existing: acc.existing + 1}
        {:error, changeset} -> %{acc | errors: acc.errors ++ [{index, changeset}]}
      end
    end)
  end

  @doc """
  Reads every source of the `:inbox` config, and adds their changes.
  Returns each source's result, by its name: `{:ok, counts}` (as
  `add_many/2`), or `{:error, reason}`, logged. With the `:digest`
  config's `every: :ingest`, new changes start a digest
  (`Tayori.Digest.after_ingest/1`).
  """
  @spec ingest() :: %{String.t() => {:ok, map()} | {:error, term()}}
  def ingest do
    config = Config.get()

    results =
      Map.new(config.inbox.sources, fn {module, opts} ->
        name = Source.name(module, opts)

        result =
          try do
            case module.changes(opts) do
              {:ok, changes} -> {:ok, add_many(changes, source: name)}
              {:error, reason} -> {:error, reason}
            end
          rescue
            error -> {:error, Exception.message(error)}
          end

        with {:error, reason} <- result do
          Logger.warning("Tayori could not read the source #{name}: #{inspect(reason)}")
        end

        {name, result}
      end)

    results
    |> Enum.map(fn
      {_name, {:ok, %{added: added}}} -> added
      _error -> 0
    end)
    |> Enum.sum()
    |> Tayori.Digest.after_ingest()

    results
  end

  @doc """
  The changes, the newest first. Options: `:state` (`"new"`, `"drafted"`,
  `"hidden"`), `:source`, `:audience`, `:entry_id`, `:ids`, `:limit`
  (100).
  """
  @spec list(keyword()) :: [Change.t()]
  def list(opts \\ []) do
    config = Config.get()

    Change
    |> filter(opts)
    |> order_by([c], desc: c.occurred_at, desc: c.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> config.repo.all(prefix: config.prefix)
  end

  defp filter(query, opts) do
    Enum.reduce(opts, query, fn
      {:state, state}, q when is_binary(state) -> where(q, [c], c.state == ^state)
      {:source, source}, q when is_binary(source) -> where(q, [c], c.source == ^source)
      {:audience, audience}, q when is_binary(audience) -> where(q, [c], c.audience == ^audience)
      {:entry_id, id}, q when is_binary(id) -> where(q, [c], c.entry_id == ^id)
      {:ids, ids}, q when is_list(ids) -> where(q, [c], c.id in ^ids)
      {:since, %DateTime{} = at}, q -> where(q, [c], c.occurred_at >= ^at)
      {:until, %DateTime{} = at}, q -> where(q, [c], c.occurred_at < ^at)
      _other, q -> q
    end)
  end

  @doc """
  The changes waiting for a digest: new, and for the public. Options:
  `:ids` (only these), `:since` and `:until` (when they happened).
  """
  @spec pending(keyword()) :: [Change.t()]
  def pending(opts \\ []) do
    config = Config.get()

    Change
    |> where([c], c.state == "new" and c.audience == "public")
    |> filter(Keyword.take(opts, [:ids, :since, :until]))
    |> order_by([c], desc: c.highlight, asc: c.occurred_at)
    |> config.repo.all(prefix: config.prefix)
  end

  @doc "A change by its id, or nil."
  @spec get(Ecto.UUID.t()) :: Change.t() | nil
  def get(id) do
    config = Config.get()

    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> config.repo.get(Change, uuid, prefix: config.prefix)
      :error -> nil
    end
  end

  @doc "Changes what a change says: its title, body, category, audience, segments, highlight."
  @spec update(Change.t(), map()) :: {:ok, Change.t()} | {:error, Ecto.Changeset.t()}
  def update(%Change{} = change, attrs) do
    config = Config.get()

    change
    |> Change.edit_changeset(attrs)
    |> config.repo.update(prefix: config.prefix)
    |> broadcast()
  end

  @doc "Puts a change aside: no digest takes it."
  @spec hide(Change.t()) :: {:ok, Change.t()}
  def hide(%Change{} = change), do: put_state(change, "hidden", change.entry_id)

  @doc "Brings back a change put aside, or one drafted whose entry is gone."
  @spec restore(Change.t()) :: {:ok, Change.t()}
  def restore(%Change{} = change), do: put_state(change, "new", nil)

  @doc false
  # The changes a digest put in an entry.
  @spec drafted([Ecto.UUID.t()], Ecto.UUID.t()) :: non_neg_integer()
  def drafted(ids, entry_id) do
    config = Config.get()

    {count, _} =
      from(c in Change, where: c.id in ^ids)
      |> config.repo.update_all(
        [set: [state: "drafted", entry_id: entry_id, updated_at: DateTime.utc_now()]],
        prefix: config.prefix
      )

    Tayori.broadcast({Tayori, :inbox, nil})
    count
  end

  defp put_state(change, state, entry_id) do
    config = Config.get()

    change
    |> Ecto.Changeset.change(state: state, entry_id: entry_id)
    |> config.repo.update(prefix: config.prefix)
    |> broadcast()
  end

  defp broadcast({:ok, change} = result) do
    Tayori.broadcast({Tayori, :inbox, change.id})
    result
  end

  defp broadcast(error), do: error

  @doc "How many changes are in each state."
  @spec counts() :: %{String.t() => non_neg_integer()}
  def counts do
    config = Config.get()

    from(c in Change, group_by: c.state, select: {c.state, count()})
    |> config.repo.all(prefix: config.prefix)
    |> Map.new()
    |> then(&Map.merge(Map.new(Change.states(), fn state -> {state, 0} end), &1))
  end

  # A change as it is added: its source, its audience and its category
  # when it does not say, and when it happened.
  defp prepare(attrs, opts, config) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    source = attrs["source"] || Keyword.get(opts, :source, "app")
    kind = attrs["kind"] && attrs["kind"] |> to_string() |> String.trim() |> String.downcase()

    attrs =
      attrs
      |> Map.put("source", source)
      |> Map.put_new("audience", config.inbox.audience)
      |> Map.update("audience", config.inbox.audience, &(&1 || config.inbox.audience))
      |> Map.put("category", attrs["category"] || category(kind, config))
      |> Map.put_new_lazy("occurred_at", &DateTime.utc_now/0)
      |> Map.update("occurred_at", DateTime.utc_now(), &(&1 || DateTime.utc_now()))

    Change.changeset(%Change{}, attrs)
  end

  defp category(nil, _config), do: nil

  defp category(kind, config) do
    Map.get(config.inbox.kinds, kind) ||
      if Map.has_key?(Categories.by_key(), kind), do: kind
  end
end
