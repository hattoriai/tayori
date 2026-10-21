defmodule Tayori.Audience do
  @moduledoc ~S"""
  Who the app's people are, for the campaigns, and what Tayori may know of
  them. The app writes one module, from its own schemas, and gives it to
  the `:campaigns` option (`Tayori.Config`):

      defmodule MyApp.TayoriAudience do
        @behaviour Tayori.Audience
        import Ecto.Query

        @impl true
        def query, do: from(u in MyApp.User, as: :person, where: is_nil(u.deleted_at))

        @impl true
        def where_ids(query, ids) do
          ids = for "user:" <> id <- ids, do: id
          where(query, [person: u], u.id in ^ids)
        end

        @impl true
        def recipient(%MyApp.User{} = u) do
          %Tayori.Recipient{
            id: "user:#{u.id}",
            email: u.email,
            name: u.name,
            locale: u.locale,
            since: u.inserted_at,
            data: %{"first_name" => u.first_name}
          }
        end

        @impl true
        def person_id, do: dynamic([person: u], fragment("'user:' || CAST(? AS TEXT)", u.id))

        @impl true
        def attributes do
          [
            Tayori.Audience.attribute(:plan, "Plan", {:enum, [{"free", "Free"}, {"pro", "Pro"}]},
              dynamic([person: u], u.plan)),
            Tayori.Audience.attribute(:signed_up_at, "Signed up", :datetime,
              dynamic([person: u], u.inserted_at)),
            Tayori.Audience.attribute(:has_projects, "Has a project", :boolean,
              dynamic([person: u],
                exists(from p in MyApp.Project, where: p.owner_id == parent_as(:person).id)))
          ]
        end

        @impl true
        def can_email?(%Tayori.Recipient{} = r, :marketing), do: r.data["marketing_opt_in"] == true
        def can_email?(_recipient, _purpose), do: true
      end

  Tayori copies nothing: every condition (`Tayori.Conditions`) is
  compiled to SQL and runs in the app's repo, on PostgreSQL or SQLite.
  The query's binding is named `:person`; the attributes and
  `c:person_id/0` are expressions on it.

  The functions of this module read the audience of the running Tayori:
  `count/2`, `sample/3`, `each_batch/4`, `get/1` and `match?/3`. A
  condition is given as `Tayori.Conditions` takes it; `nil` is everyone.
  """

  import Ecto.Query
  import Kernel, except: [match?: 2]

  alias Tayori.Audience.Attribute
  alias Tayori.{Conditions, Config, Recipient}

  @typedoc "Why a letter is sent: what the product needs, or marketing."
  @type purpose :: :product | :marketing

  @doc "The people of the app, as an Ecto query with the binding `:person`."
  @callback query() :: Ecto.Query.t()

  @doc "The query, narrowed to the people of these ids (`Tayori.Recipient` ids)."
  @callback where_ids(Ecto.Query.t(), [String.t()]) :: Ecto.Query.t()

  @doc "A row of the query, as a `Tayori.Recipient`."
  @callback recipient(row :: term()) :: Recipient.t()

  @doc """
  The facts conditions may test, each made with `attribute/5`. Without
  this function, there are none: conditions test events and segments.
  """
  @callback attributes() :: [Attribute.t()]

  @doc """
  Whether a person may get a letter of a purpose: their consent, as the
  app keeps it. Without this function, everyone may.
  """
  @callback can_email?(Recipient.t(), purpose()) :: boolean()

  @doc """
  The events the app tracks (`Tayori.track/3`), offered in the admin:
  `[{name, label}]`. Any name may be tracked anyway.
  """
  @callback events() :: [{String.t(), String.t()}]

  @doc """
  The order the people are walked in, for batches. Without this function,
  by the `id` of the `:person` binding.
  """
  @callback order(Ecto.Query.t()) :: Ecto.Query.t()

  @doc """
  The id of the person as SQL, the same string `c:recipient/1` gives:
  `dynamic([person: u], fragment("'user:' || CAST(? AS TEXT)", u.id))`.
  Conditions on events need it: without it, they are refused.
  """
  @callback person_id() :: Ecto.Query.dynamic_expr()

  @optional_callbacks attributes: 0, can_email?: 2, events: 0, order: 1, person_id: 0

  @doc """
  An attribute: a key (an atom or a string), its label, its type (see
  `Tayori.Audience.Attribute`) and its expression, a `dynamic` on the
  `:person` binding.

  Options: `:description` - a line for the admin.

      Tayori.Audience.attribute(:plan, "Plan", {:enum, [{"free", "Free"}, {"pro", "Pro"}]},
        dynamic([person: u], u.plan))
  """
  @spec attribute(
          atom() | String.t(),
          String.t(),
          Attribute.type(),
          Ecto.Query.dynamic_expr(),
          keyword()
        ) :: Attribute.t()
  def attribute(key, label, type, expr, opts \\ []) do
    key = to_string(key)

    unless key =~ ~r/\A[a-z][a-z0-9_]{0,63}\z/ do
      raise ArgumentError,
            "the key of an attribute is lowercase letters, digits and _, got: #{inspect(key)}"
    end

    unless is_binary(label) and label != "" do
      raise ArgumentError, "the label of the attribute #{key} must be a string"
    end

    unless Attribute.type?(type) do
      raise ArgumentError,
            "the type of the attribute #{key} must be :string, :integer, :boolean, :datetime, " <>
              ":date or {:enum, [{value, label}]}, got: #{inspect(type)}"
    end

    unless Kernel.match?(%Ecto.Query.DynamicExpr{}, expr) do
      raise ArgumentError,
            "the expression of the attribute #{key} must be a dynamic, " <>
              "such as dynamic([person: u], u.plan)"
    end

    case Keyword.split(opts, [:description]) do
      {opts, []} ->
        %Attribute{
          key: key,
          label: label,
          type: type,
          expr: expr,
          description: opts[:description]
        }

      {_opts, other} ->
        raise ArgumentError,
              "an attribute takes :description, got: #{inspect(Keyword.keys(other))}"
    end
  end

  @doc "How many people match a condition, at a time (now)."
  @spec count(Conditions.t(), DateTime.t()) :: non_neg_integer()
  def count(condition, now \\ DateTime.utc_now()) do
    {config, audience} = audience!()

    audience
    |> matching(condition, now)
    |> exclude(:order_by)
    |> config.repo.aggregate(:count)
  end

  @doc "The first people who match a condition (10), as recipients."
  @spec sample(Conditions.t(), pos_integer(), DateTime.t()) :: [Recipient.t()]
  def sample(condition, limit \\ 10, now \\ DateTime.utc_now()) do
    {config, audience} = audience!()

    audience
    |> matching(condition, now)
    |> ordered(audience)
    |> limit(^limit)
    |> config.repo.all()
    |> Enum.map(&audience.recipient/1)
  end

  @doc """
  Walks every person who matches a condition, in batches of `size`
  recipients: `fun` gets each batch, in the order of `c:order/1`.
  """
  @spec each_batch(Conditions.t(), pos_integer(), ([Recipient.t()] -> term()), DateTime.t()) ::
          :ok
  def each_batch(condition, size, fun, now \\ DateTime.utc_now())
      when is_integer(size) and size > 0 and is_function(fun, 1) do
    {config, audience} = audience!()
    query = audience |> matching(condition, now) |> ordered(audience)
    walk(config, audience, query, size, 0, fun)
  end

  defp walk(config, audience, query, size, offset, fun) do
    rows = query |> limit(^size) |> offset(^offset) |> config.repo.all()

    if rows != [], do: fun.(Enum.map(rows, &audience.recipient/1))

    if length(rows) == size,
      do: walk(config, audience, query, size, offset + size, fun),
      else: :ok
  end

  @doc "A person by their id, as a recipient, or nil."
  @spec get(String.t()) :: Recipient.t() | nil
  def get(id) when is_binary(id) do
    {config, audience} = audience!()

    case audience.query() |> audience.where_ids([id]) |> limit(1) |> config.repo.one() do
      nil -> nil
      row -> audience.recipient(row)
    end
  end

  @doc "Whether a person matches a condition, at a time (now), in one query."
  @spec match?(String.t(), Conditions.t(), DateTime.t()) :: boolean()
  def match?(id, condition, now \\ DateTime.utc_now()) when is_binary(id) do
    {config, audience} = audience!()

    audience
    |> matching(condition, now)
    |> audience.where_ids([id])
    |> exclude(:order_by)
    |> config.repo.exists?()
  end

  defp matching(audience, condition, now) do
    where(audience.query(), ^Conditions.compile(condition, attributes(audience), now))
  end

  defp ordered(query, audience) do
    if exports?(audience, :order, 1),
      do: audience.order(query),
      else: order_by(query, [person: p], asc: p.id)
  end

  defp audience! do
    case Config.get() do
      %Config{campaigns: %{audience: audience}} = config ->
        {config, audience}

      _off ->
        raise ArgumentError, "the :campaigns module is off: add it to the :modules of Tayori"
    end
  end

  @doc false
  # The audience of the running Tayori, or nil when campaigns are off.
  def current do
    case Config.get() do
      %Config{campaigns: %{audience: audience}} -> audience
      _off -> nil
    end
  end

  @doc false
  def attributes(audience) do
    if exports?(audience, :attributes, 0), do: audience.attributes(), else: []
  end

  @doc false
  def events(audience) do
    if exports?(audience, :events, 0), do: audience.events(), else: []
  end

  @doc false
  def person_id(audience) do
    if exports?(audience, :person_id, 0), do: audience.person_id()
  end

  @doc false
  def can_email?(audience, %Recipient{} = recipient, purpose)
      when purpose in [:product, :marketing] do
    if exports?(audience, :can_email?, 2),
      do: audience.can_email?(recipient, purpose) == true,
      else: true
  end

  defp exports?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end
end
