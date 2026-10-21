defmodule Tayori.Conditions do
  @moduledoc ~S"""
  Conditions on the app's people: who a campaign is for, its goal, when a
  step is skipped, a segment. A condition is data, kept as a map with
  string keys:

      %{"all" => [c, ...]}    %{"any" => [c, ...]}    %{"not" => c}
      %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}
      %{"event" => "story_published", "op" => "happened", "within_days" => 30}
      %{"segment" => "<segment id>", "op" => "in"}

  `%{"all" => []}` (or nil) is everyone; `%{"any" => []}` no one.

  ## Operators

  By the type of the attribute (`Tayori.Audience.Attribute`):

    * string - `eq`, `neq`, `contains`, `starts_with`, `set`, `not_set`;
    * integer - `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `set`, `not_set`;
    * boolean - `true`, `false`;
    * datetime and date - `before`, `after` (an ISO 8601 date or time),
      `more_than_days_ago`, `less_than_days_ago` (a positive number of
      days), `set`, `not_set`;
    * enum - `in`, `not_in` (a list of the enum's values).

  An event `happened` or `not_happened`, ever or in the last
  `within_days`. A person is `in` or `not_in` a segment
  (`Tayori.Campaigns.Segment`).

  ## How they run

  `compile/4` makes a condition an Ecto `dynamic` on the `:person`
  binding of the audience's query: the condition runs in the app's
  database, on PostgreSQL or SQLite, with the same results.

    * The strings are compared without case (`lower` of both sides; on
      SQLite, of ASCII letters only). `contains` and `starts_with` take
      the value as text, `%` and `_` too.
    * A person with no value (`NULL`) matches no comparison, and matches
      `neq` and `not_in`: "Plan is not Pro" is everyone but the Pro.
      Every rule is true or false, never `NULL`, so `not` is what it
      says.
    * Times are computed in Elixir (`now` less n days), then compared as
      parameters. A date "after" is after that whole day.
    * An event is a row of `tayori_events` with the person's id, which
      the audience gives as SQL (`c:Tayori.Audience.person_id/0`): without
      it, events are refused.
    * A segment is its condition, inlined. A segment that leads back to
      itself is refused.

  A count of something is an `:integer` attribute made of a correlated
  scalar subquery, on both databases:

      dynamic([person: u],
        subquery(from p in MyApp.Project, where: p.owner_id == parent_as(:person).id,
          select: count())
      )

  An attribute that no longer exists, or a segment, compiles to false,
  and Tayori logs it once.

  ## Limits

  A condition is at most 5 groups deep and has at most 50 rules.
  """

  import Ecto.Query

  alias Tayori.Audience
  alias Tayori.Audience.Attribute
  alias Tayori.Campaigns.{Event, Segment}
  alias Tayori.Config

  require Logger

  @typedoc "A condition: a map as the module doc says, or nil for everyone."
  @type t :: map() | nil

  @max_depth 5
  @max_leaves 50

  @operators %{
    string: ~w(eq neq contains starts_with set not_set),
    integer: ~w(eq neq gt gte lt lte set not_set),
    boolean: ~w(true false),
    datetime: ~w(before after more_than_days_ago less_than_days_ago set not_set),
    date: ~w(before after more_than_days_ago less_than_days_ago set not_set),
    enum: ~w(in not_in)
  }

  @event_ops ~w(happened not_happened)
  @segment_ops ~w(in not_in)
  @names ~w(attribute event op)

  @doc "The operators of a type of attribute."
  @spec operators(Attribute.type() | atom()) :: [String.t()]
  def operators(type), do: Map.fetch!(@operators, Attribute.type_name(type))

  @doc "The operators of an event."
  @spec event_operators() :: [String.t()]
  def event_operators, do: @event_ops

  @doc "The most groups deep and the most rules of a condition."
  @spec limits() :: %{depth: pos_integer(), leaves: pos_integer()}
  def limits, do: %{depth: @max_depth, leaves: @max_leaves}

  # ── Validation ──────────────────────────────────────────────────

  @doc """
  Checks a condition against the audience's attributes, and gives it
  back normalized (string keys, values of their type), or the errors in
  words.

  Options:

    * `:events` - whether conditions on events are allowed: by default,
      when the audience of the running Tayori has `person_id/0`.
    * `:segment_id` - the segment the condition is of, which it must not
      lead back to.
  """
  @spec validate(t(), [Attribute.t()], keyword()) :: {:ok, map()} | {:error, [String.t()]}
  def validate(condition, attributes, opts \\ [])
  def validate(nil, attributes, opts), do: validate(%{"all" => []}, attributes, opts)

  def validate(condition, attributes, opts) do
    ctx = %{
      attributes: Map.new(attributes, &{&1.key, &1}),
      events?: Keyword.get_lazy(opts, :events, &events?/0)
    }

    {normalized, errors} = check(stringify(condition), ctx)

    errors =
      errors ++
        depth_error(normalized) ++ leaves_error(normalized) ++ cycle_error(normalized, opts)

    case Enum.uniq(errors) do
      [] -> {:ok, normalized}
      errors -> {:error, errors}
    end
  end

  defp events? do
    case Audience.current() do
      nil -> false
      audience -> Audience.person_id(audience) != nil
    end
  end

  # String keys; the names an Elixir caller gives as atoms, as strings.
  defp stringify(%{} = map) when not is_struct(map) do
    Map.new(map, fn {key, value} ->
      key = to_string(key)
      {key, if(key in @names, do: name(value), else: stringify(value))}
    end)
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value

  defp name(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp name(value), do: stringify(value)

  defp check(%{"all" => list} = group, ctx) when map_size(group) == 1, do: group("all", list, ctx)
  defp check(%{"any" => list} = group, ctx) when map_size(group) == 1, do: group("any", list, ctx)

  defp check(%{"not" => condition} = group, ctx) when map_size(group) == 1 do
    {condition, errors} = check(condition, ctx)
    {%{"not" => condition}, errors}
  end

  defp check(%{"attribute" => key} = leaf, ctx) when is_binary(key) do
    case Map.fetch(ctx.attributes, key) do
      {:ok, attribute} -> attribute_leaf(attribute, leaf)
      :error -> {leaf, ["Unknown attribute #{inspect(key)}."]}
    end
  end

  defp check(%{"event" => name} = leaf, ctx) when is_binary(name) do
    name = String.trim(name)
    op = leaf["op"]

    errors =
      Enum.reject(
        [
          not ctx.events? &&
            "Conditions on events need the audience's person_id/0.",
          (name == "" or String.length(name) > 64) &&
            "The name of an event is 1 to 64 characters.",
          op not in @event_ops &&
            ~s(An event "happened" or "not_happened", not #{inspect(op)}.)
        ],
        &(&1 in [false, nil])
      )

    case days(leaf["within_days"]) do
      {:ok, days} ->
        leaf = %{"event" => name, "op" => op}
        leaf = if days, do: Map.put(leaf, "within_days", days), else: leaf
        {leaf, errors}

      :error ->
        {leaf, errors ++ ["The days of an event are a positive number."]}
    end
  end

  defp check(%{"segment" => id} = leaf, _ctx) when is_binary(id) do
    op = leaf["op"] || "in"
    leaf = %{"segment" => id, "op" => op}

    errors =
      Enum.reject(
        [
          op not in @segment_ops &&
            ~s(A person is "in" or "not_in" a segment, not #{inspect(op)}.),
          segment(id) == nil && "No segment with the id #{inspect(id)}."
        ],
        &(&1 in [false, nil])
      )

    {leaf, errors}
  end

  defp check(other, _ctx), do: {other, ["Not a condition: #{inspect(other)}."]}

  defp group(kind, list, ctx) when is_list(list) do
    {conditions, errors} =
      list
      |> Enum.map(&check(&1, ctx))
      |> Enum.unzip()

    {%{kind => conditions}, List.flatten(errors)}
  end

  defp group(kind, other, _ctx),
    do: {%{kind => other}, [~s("#{kind}" takes a list of conditions.)]}

  defp days(nil), do: {:ok, nil}
  defp days(days), do: positive(days)

  defp positive(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp positive(text) when is_binary(text) do
    case Integer.parse(String.trim(text)) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp positive(_other), do: :error

  defp attribute_leaf(%Attribute{} = attribute, leaf) do
    op = leaf["op"]
    type = Attribute.type_name(attribute)
    base = %{"attribute" => attribute.key, "op" => op}

    if op in operators(type) do
      case value(attribute.type, op, leaf["value"]) do
        :none -> {base, []}
        {:ok, value} -> {Map.put(base, "value", value), []}
        {:error, message} -> {leaf, ["#{attribute.label} #{message}"]}
      end
    else
      {leaf,
       [
         "#{attribute.label} cannot be #{inspect(op)}: " <>
           "its operators are #{Enum.join(operators(type), ", ")}."
       ]}
    end
  end

  defp value(_type, op, _value) when op in ~w(set not_set true false), do: :none

  defp value(:string, _op, value) when is_binary(value) do
    cond do
      value == "" -> {:error, "needs a value."}
      String.length(value) > 255 -> {:error, "takes a value of 255 characters at most."}
      true -> {:ok, value}
    end
  end

  defp value(:string, _op, _value), do: {:error, "needs a text value."}

  defp value(:integer, _op, value) when is_integer(value), do: {:ok, value}

  defp value(:integer, _op, value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "needs a whole number."}
    end
  end

  defp value(:integer, _op, _value), do: {:error, "needs a whole number."}

  defp value(type, op, value)
       when type in [:datetime, :date] and op in ~w(more_than_days_ago less_than_days_ago) do
    case positive(value) do
      {:ok, n} -> {:ok, n}
      :error -> {:error, "needs a positive number of days."}
    end
  end

  defp value(type, _op, value) when type in [:datetime, :date] do
    case moment(value) do
      {:ok, %Date{} = date} -> {:ok, Date.to_iso8601(date)}
      {:ok, %DateTime{} = at} -> {:ok, DateTime.to_iso8601(at)}
      :error -> {:error, "needs a date or a time, in ISO 8601 (2026-01-31)."}
    end
  end

  defp value({:enum, values}, _op, value) do
    allowed = Enum.map(values, &elem(&1, 0))
    given = if is_binary(value), do: [value], else: value

    cond do
      not is_list(given) or given == [] ->
        {:error, "needs one or more of #{Enum.join(allowed, ", ")}."}

      Enum.all?(given, &(&1 in allowed)) ->
        {:ok, Enum.uniq(given)}

      true ->
        {:error, "is one of #{Enum.join(allowed, ", ")}, not #{inspect(given -- allowed)}."}
    end
  end

  # A date, or a time with its offset (UTC when it has none).
  defp moment(%Date{} = date), do: {:ok, date}
  defp moment(%DateTime{} = at), do: {:ok, DateTime.shift_zone!(at, "Etc/UTC")}

  defp moment(text) when is_binary(text) do
    text = String.trim(text)

    with {:error, _} <- Date.from_iso8601(text),
         {:error, _} <- datetime(text) do
      :error
    end
  end

  defp moment(_other), do: :error

  defp datetime(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} ->
        {:ok, at}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(text) do
          {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
          error -> error
        end
    end
  end

  defp depth_error(condition) do
    if depth(condition) > @max_depth,
      do: ["A condition is at most #{@max_depth} groups deep."],
      else: []
  end

  defp leaves_error(condition) do
    if leaves(condition) > @max_leaves,
      do: ["A condition has at most #{@max_leaves} rules."],
      else: []
  end

  defp depth(%{"all" => list}) when is_list(list), do: 1 + max_depth(list)
  defp depth(%{"any" => list}) when is_list(list), do: 1 + max_depth(list)
  defp depth(%{"not" => condition}), do: 1 + depth(condition)
  defp depth(_leaf), do: 0

  defp max_depth(list), do: list |> Enum.map(&depth/1) |> Enum.max(fn -> 0 end)

  defp leaves(%{"all" => list}) when is_list(list), do: list |> Enum.map(&leaves/1) |> Enum.sum()
  defp leaves(%{"any" => list}) when is_list(list), do: list |> Enum.map(&leaves/1) |> Enum.sum()
  defp leaves(%{"not" => condition}), do: leaves(condition)
  defp leaves(_leaf), do: 1

  # The segments a condition names, and theirs, as far as they go: the
  # segment being saved must not be among them.
  defp cycle_error(condition, opts) do
    case opts[:segment_id] do
      nil ->
        []

      id ->
        if id in reachable(segment_ids(condition), MapSet.new()),
          do: ["The segment refers back to itself."],
          else: []
    end
  end

  defp reachable([], seen), do: MapSet.to_list(seen)

  defp reachable([id | rest], seen) do
    if MapSet.member?(seen, id) do
      reachable(rest, seen)
    else
      named =
        case segment(id) do
          %Segment{condition: condition} -> segment_ids(stringify(condition))
          nil -> []
        end

      reachable(named ++ rest, MapSet.put(seen, id))
    end
  end

  @doc false
  # The ids of the segments a condition names, inlined or not.
  @spec segment_ids(t()) :: [String.t()]
  def segment_ids(%{"all" => list}) when is_list(list), do: Enum.flat_map(list, &segment_ids/1)
  def segment_ids(%{"any" => list}) when is_list(list), do: Enum.flat_map(list, &segment_ids/1)
  def segment_ids(%{"not" => condition}), do: segment_ids(condition)
  def segment_ids(%{"segment" => id}) when is_binary(id), do: [id]
  def segment_ids(_other), do: []

  defp segment(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        config = Config.get()
        config.repo.get(Segment, uuid, prefix: config.prefix)

      :error ->
        nil
    end
  end

  # ── Compilation ─────────────────────────────────────────────────

  @doc """
  A condition as an Ecto `dynamic` on the `:person` binding, at a time:

      where(audience.query(), ^Tayori.Conditions.compile(condition, attributes, now))

  Options: `:person_id` - the person's id as SQL, for events (by default,
  the audience's `person_id/0`).
  """
  @spec compile(t(), [Attribute.t()], DateTime.t(), keyword()) :: Ecto.Query.dynamic_expr()
  def compile(condition, attributes, now, opts \\ [])
  def compile(nil, _attributes, _now, _opts), do: dynamic(true)

  def compile(condition, attributes, %DateTime{} = now, opts) do
    ctx = %{
      attributes: Map.new(attributes, &{&1.key, &1}),
      now: DateTime.shift_zone!(now, "Etc/UTC"),
      person_id: Keyword.get_lazy(opts, :person_id, &person_id/0),
      seen: MapSet.new()
    }

    build(stringify(condition), ctx)
  end

  defp person_id do
    case Audience.current() do
      nil -> nil
      audience -> Audience.person_id(audience)
    end
  end

  defp build(%{"all" => []}, _ctx), do: dynamic(true)
  defp build(%{"any" => []}, _ctx), do: dynamic(false)

  defp build(%{"all" => [first | rest]}, ctx) do
    Enum.reduce(rest, build(first, ctx), fn condition, acc ->
      dynamic(^acc and ^build(condition, ctx))
    end)
  end

  defp build(%{"any" => [first | rest]}, ctx) do
    Enum.reduce(rest, build(first, ctx), fn condition, acc ->
      dynamic(^acc or ^build(condition, ctx))
    end)
  end

  defp build(%{"not" => condition}, ctx), do: dynamic(not (^build(condition, ctx)))

  defp build(%{"attribute" => key} = leaf, ctx) do
    with {:ok, attribute} <- Map.fetch(ctx.attributes, key),
         true <- leaf["op"] in operators(attribute.type),
         value when value != :invalid <- compile_value(attribute.type, leaf["op"], leaf["value"]) do
      attribute(Attribute.type_name(attribute), leaf["op"], attribute.expr, value, ctx.now)
    else
      _ ->
        nothing(
          {:attribute, key},
          "the attribute #{inspect(key)} is unknown or its rule is not valid"
        )
    end
  end

  defp build(%{"event" => name, "op" => op} = leaf, ctx) when op in @event_ops do
    case ctx.person_id do
      nil ->
        nothing({:events, name}, "events need the audience's person_id/0")

      person_id ->
        happened = dynamic(^person_id in subquery(events(name, leaf["within_days"], ctx.now)))
        if op == "happened", do: happened, else: dynamic(not (^happened))
    end
  end

  defp build(%{"segment" => id, "op" => op}, ctx) when op in @segment_ops do
    with false <- MapSet.member?(ctx.seen, id),
         %Segment{condition: condition} <- segment(id) do
      inner = build(stringify(condition), %{ctx | seen: MapSet.put(ctx.seen, id)})
      if op == "in", do: inner, else: dynamic(not (^inner))
    else
      _ -> nothing({:segment, id}, "the segment #{inspect(id)} is gone, or leads back to itself")
    end
  end

  defp build(other, _ctx),
    do: nothing({:condition, other}, "#{inspect(other)} is not a condition")

  # A rule that cannot run matches no one, said once to the logs.
  defp nothing(key, message) do
    key = {__MODULE__, :warned, key}

    unless :persistent_term.get(key, false) do
      Logger.warning("Tayori compiles a condition to false: #{message}")
      :persistent_term.put(key, true)
    end

    dynamic(false)
  end

  defp compile_value(type, op, value) do
    case value(type, op, value) do
      :none -> nil
      {:ok, value} -> value
      {:error, _} -> :invalid
    end
  end

  defp events(name, within_days, now) do
    config = Config.get()
    query = from(e in Event, where: e.name == ^name, select: e.person)

    query =
      if within_days,
        do: where(query, [e], e.occurred_at >= ^DateTime.add(now, -within_days, :day)),
        else: query

    if config.prefix, do: %{query | from: %{query.from | prefix: config.prefix}}, else: query
  end

  # String: compared without case.
  defp attribute(:string, "eq", x, v, _now),
    do: dynamic(not is_nil(^x) and fragment("lower(?)", ^x) == fragment("lower(?)", ^v))

  defp attribute(:string, "neq", x, v, _now),
    do: dynamic(is_nil(^x) or fragment("lower(?)", ^x) != fragment("lower(?)", ^v))

  defp attribute(:string, "contains", x, v, _now), do: like(x, "%" <> escape(v) <> "%")
  defp attribute(:string, "starts_with", x, v, _now), do: like(x, escape(v) <> "%")
  defp attribute(:string, "set", x, _v, _now), do: dynamic(not is_nil(^x) and ^x != "")
  defp attribute(:string, "not_set", x, _v, _now), do: dynamic(is_nil(^x) or ^x == "")

  # Integer.
  defp attribute(:integer, "eq", x, v, _now), do: dynamic(not is_nil(^x) and ^x == ^v)
  defp attribute(:integer, "neq", x, v, _now), do: dynamic(is_nil(^x) or ^x != ^v)
  defp attribute(:integer, "gt", x, v, _now), do: dynamic(not is_nil(^x) and ^x > ^v)
  defp attribute(:integer, "gte", x, v, _now), do: dynamic(not is_nil(^x) and ^x >= ^v)
  defp attribute(:integer, "lt", x, v, _now), do: dynamic(not is_nil(^x) and ^x < ^v)
  defp attribute(:integer, "lte", x, v, _now), do: dynamic(not is_nil(^x) and ^x <= ^v)

  # Boolean: NULL is false.
  defp attribute(:boolean, "true", x, _v, _now), do: dynamic(coalesce(^x, false))
  defp attribute(:boolean, "false", x, _v, _now), do: dynamic(not coalesce(^x, false))

  # Enum.
  defp attribute(:enum, "in", x, v, _now), do: dynamic(not is_nil(^x) and ^x in ^v)
  defp attribute(:enum, "not_in", x, v, _now), do: dynamic(is_nil(^x) or ^x not in ^v)

  # Set or not, for the types that have it.
  defp attribute(_type, "set", x, _v, _now), do: dynamic(not is_nil(^x))
  defp attribute(_type, "not_set", x, _v, _now), do: dynamic(is_nil(^x))

  # Times, as parameters of the column's type.
  defp attribute(type, op, x, v, now) when type in [:datetime, :date] do
    case bound(type, op, v, now) do
      {:lt, at} -> dynamic(not is_nil(^x) and ^x < ^param(type, at))
      {:gt, at} -> dynamic(not is_nil(^x) and ^x > ^param(type, at))
      {:gte, at} -> dynamic(not is_nil(^x) and ^x >= ^param(type, at))
    end
  end

  defp param(:datetime, at), do: dynamic(type(^at, :utc_datetime_usec))
  defp param(:date, date), do: dynamic(type(^date, :date))

  # The comparison of a time rule and its bound: a date "after" is after
  # the whole day.
  defp bound(:datetime, "more_than_days_ago", n, now),
    do: {:lt, usec(DateTime.add(now, -n, :day))}

  defp bound(:datetime, "less_than_days_ago", n, now),
    do: {:gt, usec(DateTime.add(now, -n, :day))}

  defp bound(:date, "more_than_days_ago", n, now), do: {:lt, Date.add(DateTime.to_date(now), -n)}
  defp bound(:date, "less_than_days_ago", n, now), do: {:gt, Date.add(DateTime.to_date(now), -n)}

  defp bound(type, op, value, _now) do
    {:ok, moment} = moment(value)

    case {type, op, moment} do
      {:datetime, "before", %Date{} = date} -> {:lt, midnight(date)}
      {:datetime, "after", %Date{} = date} -> {:gte, midnight(Date.add(date, 1))}
      {:datetime, "before", at} -> {:lt, usec(at)}
      {:datetime, "after", at} -> {:gt, usec(at)}
      {:date, "before", moment} -> {:lt, to_date(moment)}
      {:date, "after", moment} -> {:gt, to_date(moment)}
    end
  end

  defp midnight(date), do: DateTime.new!(date, ~T[00:00:00.000000], "Etc/UTC")
  defp to_date(%Date{} = date), do: date
  defp to_date(%DateTime{} = at), do: DateTime.to_date(at)
  defp usec(%DateTime{microsecond: {value, _}} = at), do: %{at | microsecond: {value, 6}}

  defp like(x, pattern),
    do: dynamic(not is_nil(^x) and fragment("lower(?) LIKE lower(?) ESCAPE '\\'", ^x, ^pattern))

  defp escape(value), do: String.replace(value, ~r/[\\%_]/, "\\\\\\0")

  # ── Description ─────────────────────────────────────────────────

  @doc """
  A condition in words, for the admin and the agents: "Plan is Pro and
  signed up more than 7 days ago".

  Options: `:events` - the labels of the events, `[{name, label}]` (by
  default, the audience's `events/0`).
  """
  @spec describe(t(), [Attribute.t()], keyword()) :: String.t()
  def describe(condition, attributes, opts \\ []) do
    ctx = %{
      attributes: Map.new(attributes, &{&1.key, &1}),
      events: Map.new(Keyword.get_lazy(opts, :events, &event_labels/0))
    }

    condition
    |> stringify()
    |> phrase(ctx, true)
    |> capitalize()
  end

  defp event_labels do
    case Audience.current() do
      nil -> []
      audience -> Audience.events(audience)
    end
  end

  defp phrase(nil, _ctx, _top), do: "everyone"
  defp phrase(%{"all" => []}, _ctx, _top), do: "everyone"
  defp phrase(%{"any" => []}, _ctx, _top), do: "no one"
  defp phrase(%{"all" => [one]}, ctx, top), do: phrase(one, ctx, top)
  defp phrase(%{"any" => [one]}, ctx, top), do: phrase(one, ctx, top)
  defp phrase(%{"all" => list}, ctx, top) when is_list(list), do: phrases(list, " and ", ctx, top)
  defp phrase(%{"any" => list}, ctx, top) when is_list(list), do: phrases(list, " or ", ctx, top)

  defp phrase(%{"not" => condition}, ctx, _top),
    do: "not (" <> phrase(condition, ctx, true) <> ")"

  defp phrase(%{"attribute" => key, "op" => op} = leaf, ctx, _top) do
    case Map.fetch(ctx.attributes, key) do
      {:ok, attribute} -> lower(attribute.label) <> " " <> rule(attribute, op, leaf["value"])
      :error -> ~s(the unknown attribute "#{key}")
    end
    |> String.trim_trailing()
  end

  defp phrase(%{"event" => name, "op" => op} = leaf, ctx, _top) do
    label = ~s("#{Map.get(ctx.events, name, name)}")

    within =
      case leaf["within_days"] do
        nil -> ""
        1 -> " in the last day"
        n -> " in the last #{n} days"
      end

    case {op, within} do
      {"happened", _} -> label <> " happened" <> within
      {_, ""} -> label <> " never happened"
      {_, within} -> label <> " did not happen" <> within
    end
  end

  defp phrase(%{"segment" => id, "op" => op}, _ctx, _top) do
    name =
      case segment(id) do
        %Segment{name: name} -> ~s(the segment "#{name}")
        nil -> "a segment that no longer exists"
      end

    if op == "not_in", do: "not in " <> name, else: "in " <> name
  end

  defp phrase(other, _ctx, _top), do: inspect(other)

  defp phrases(list, separator, ctx, top) do
    text = Enum.map_join(list, separator, &phrase(&1, ctx, false))
    if top, do: text, else: "(" <> text <> ")"
  end

  defp rule(_attribute, "set", _value), do: "is set"
  defp rule(_attribute, "not_set", _value), do: "is not set"
  defp rule(_attribute, "true", _value), do: ""
  defp rule(_attribute, "false", _value), do: "is false"
  defp rule(_attribute, "eq", value), do: "is #{show(value)}"
  defp rule(_attribute, "neq", value), do: "is not #{show(value)}"
  defp rule(_attribute, "contains", value), do: "contains #{show(value)}"
  defp rule(_attribute, "starts_with", value), do: "starts with #{show(value)}"
  defp rule(_attribute, "gt", value), do: "is more than #{value}"
  defp rule(_attribute, "gte", value), do: "is at least #{value}"
  defp rule(_attribute, "lt", value), do: "is less than #{value}"
  defp rule(_attribute, "lte", value), do: "is at most #{value}"
  defp rule(_attribute, "before", value), do: "before #{moment_text(value)}"
  defp rule(_attribute, "after", value), do: "after #{moment_text(value)}"
  defp rule(_attribute, "more_than_days_ago", value), do: "more than #{days_text(value)} ago"
  defp rule(_attribute, "less_than_days_ago", value), do: "less than #{days_text(value)} ago"

  defp rule(%Attribute{type: {:enum, values}}, op, value) when op in ["in", "not_in"] do
    labels = Map.new(values)
    names = Enum.map(List.wrap(value), &Map.get(labels, &1, &1))

    case {op, names} do
      {"in", names} -> "is " <> either(names, "or")
      {"not_in", [one]} -> "is not " <> one
      {"not_in", [a, b]} -> "is neither #{a} nor #{b}"
      {"not_in", names} -> "is none of " <> either(names, "and")
    end
  end

  defp rule(_attribute, op, value), do: "#{op} #{inspect(value)}"

  defp either([one], _word), do: one

  defp either(names, word) do
    {rest, [last]} = Enum.split(names, -1)
    Enum.join(rest, ", ") <> " #{word} " <> last
  end

  defp show(value) when is_binary(value), do: ~s("#{value}")
  defp show(value), do: to_string(value)

  defp days_text(1), do: "1 day"
  defp days_text(n), do: "#{n} days"

  defp moment_text(value) do
    case moment(value) do
      {:ok, %Date{} = date} -> Date.to_iso8601(date)
      {:ok, at} -> Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")
      :error -> inspect(value)
    end
  end

  # "Signed up" is "signed up" within a sentence; "URL" stays "URL".
  defp lower(<<first::utf8, second::utf8, rest::binary>> = label) do
    if String.downcase(<<second::utf8>>) == <<second::utf8>>,
      do: String.downcase(<<first::utf8>>) <> <<second::utf8, rest::binary>>,
      else: label
  end

  defp lower(label), do: label

  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalize(""), do: ""
end
