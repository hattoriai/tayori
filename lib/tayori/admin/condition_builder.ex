defmodule Tayori.Admin.ConditionBuilder do
  @moduledoc false
  # The condition builder of the campaigns' pages: a condition
  # (Tayori.Conditions) as groups of rules, which the admin edits. A group
  # is all of its rules, any of them, none of them or not all of them; a
  # rule tests an attribute of the audience, an event (when the audience
  # gives person_id/0) or a saved segment. Three groups deep at most here;
  # a deeper condition made elsewhere is shown, and kept.
  #
  # It says the condition in words (Conditions.describe/3), its errors
  # (Conditions.validate/3), and where asked, how many people match and the
  # first ten of them, counted in a task as the admin stops typing.
  #
  # The parent hears each change as {Tayori.Admin.ConditionBuilder, id,
  # condition} and gives the condition back: the builder keeps its own
  # rules while the condition it gets is the one it said.
  #
  # Attributes:
  #
  #   * :id, :label - the builder's id and its name (a legend).
  #   * :condition - a condition, or nil (everyone, or no condition).
  #   * :empty - the sentence for no rule ("Everyone.").
  #   * :hint - a line under the label.
  #   * :count - :none, :count or :sample (with the first ten people).
  #   * :segments - the saved segments, [{id, name}], for the segment rules.
  #   * :segment_id - the segment being edited, which it must not name.
  #   * :read_only - nothing changes.

  use Phoenix.LiveComponent

  import Tayori.Admin.Components, only: [icon: 1]

  alias Tayori.Audience
  alias Tayori.Audience.Attribute
  alias Tayori.Conditions

  @max_depth 3
  @group_ops [
    {"all", "All of these"},
    {"any", "Any of these"},
    {"none", "None of these"},
    {"not_all", "Not all of these"}
  ]

  @op_labels %{
    "eq" => "is",
    "neq" => "is not",
    "contains" => "contains",
    "starts_with" => "starts with",
    "set" => "is set",
    "not_set" => "is not set",
    "gt" => "is more than",
    "gte" => "is at least",
    "lt" => "is less than",
    "lte" => "is at most",
    "before" => "is before",
    "after" => "is after",
    "more_than_days_ago" => "more than … days ago",
    "less_than_days_ago" => "less than … days ago",
    "in" => "is",
    "not_in" => "is not",
    "happened" => "happened",
    "not_happened" => "did not happen"
  }

  @doc "The deepest groups the builder makes: a condition of more is kept, not made."
  def max_depth, do: @max_depth

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       tree: nil,
       emitted: :none,
       errors: [],
       sentence: nil,
       counted: nil,
       counting: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    audience = Audience.current()

    socket =
      socket
      |> assign(
        id: assigns.id,
        label: assigns.label,
        hint: assigns[:hint],
        empty: assigns[:empty] || "Everyone.",
        count: assigns[:count] || :none,
        segments: assigns[:segments] || [],
        segment_id: assigns[:segment_id],
        read_only: assigns[:read_only] || false,
        attributes: Audience.attributes(audience),
        events: Audience.events(audience),
        events?: Audience.person_id(audience) != nil
      )

    incoming = assigns[:condition]

    if socket.assigns.tree == nil or not same?(incoming, socket.assigns.emitted) do
      {:ok, socket |> assign(tree: parse(incoming), emitted: incoming) |> evaluate()}
    else
      {:ok, socket}
    end
  end

  defp same?(a, b), do: blank(a) == blank(b)

  defp blank(nil), do: %{"all" => []}
  defp blank(condition), do: condition

  # ── Events ──────────────────────────────────────────────────────

  @impl true
  def handle_event("change", %{"n" => nodes}, %{assigns: %{read_only: false}} = socket)
      when is_map(nodes) do
    tree = put_params(socket.assigns.tree, nodes, socket.assigns.attributes)
    {:noreply, socket |> assign(tree: tree) |> changed()}
  end

  def handle_event("add_rule", %{"group" => id}, %{assigns: %{read_only: false}} = socket) do
    leaf = new_leaf(socket.assigns)
    {:noreply, socket |> update_group(id, &%{&1 | children: &1.children ++ [leaf]}) |> changed()}
  end

  def handle_event("add_group", %{"group" => id}, %{assigns: %{read_only: false}} = socket) do
    if depth_of(socket.assigns.tree, id) < @max_depth do
      group = %{new_group("all") | children: [new_leaf(socket.assigns)]}

      {:noreply,
       socket |> update_group(id, &%{&1 | children: &1.children ++ [group]}) |> changed()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove", %{"node" => id}, %{assigns: %{read_only: false}} = socket) do
    {:noreply, socket |> assign(tree: remove(socket.assigns.tree, id)) |> changed()}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:count, {:ok, result}, socket),
    do: {:noreply, assign(socket, counted: result, counting: false)}

  def handle_async(:count, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, counted: :error, counting: false)}

  defp update_group(socket, id, fun),
    do: assign(socket, tree: map_node(socket.assigns.tree, id, fun))

  # The condition changed: the parent hears of it, the words and the count
  # follow.
  defp changed(socket) do
    condition = to_condition(socket.assigns.tree)
    send(self(), {__MODULE__, socket.assigns.id, condition})
    socket |> assign(emitted: condition) |> evaluate()
  end

  defp evaluate(socket) do
    %{tree: tree, attributes: attributes, events?: events?} = socket.assigns
    condition = to_condition(tree)
    opts = [events: events?, segment_id: socket.assigns.segment_id]

    case Conditions.validate(condition, attributes, opts) do
      {:ok, normalized} ->
        sentence =
          if empty?(tree),
            do: socket.assigns.empty,
            else: Conditions.describe(normalized, attributes) <> "."

        socket
        |> assign(errors: [], sentence: sentence)
        |> count(normalized)

      {:error, errors} ->
        assign(socket, errors: errors, sentence: nil, counting: false)
    end
  end

  defp count(%{assigns: %{count: :none}} = socket, _condition), do: socket

  defp count(socket, condition) do
    sample? = socket.assigns.count == :sample

    socket
    |> assign(counting: true)
    |> start_async(:count, fn ->
      now = DateTime.utc_now()

      %{
        count: Audience.count(condition, now),
        sample: if(sample?, do: Audience.sample(condition, 10, now))
      }
    end)
  end

  # ── The tree ────────────────────────────────────────────────────
  #
  # A group: %{type: :group, id, op: "all" | "any" | "none" | "not_all",
  # children}. A rule: %{type: :attribute, id, key, op, value},
  # %{type: :event, id, name, op, within_days}, %{type: :segment, id,
  # segment, op}, or %{type: :raw, id, condition} for what the builder
  # cannot show, kept as it is.

  defp new_id, do: "c" <> Integer.to_string(System.unique_integer([:positive]))

  defp new_group(op), do: %{type: :group, id: new_id(), op: op, children: []}

  defp new_leaf(%{attributes: [attribute | _]}), do: attribute_leaf(attribute)
  defp new_leaf(%{events?: true}), do: event_leaf()
  defp new_leaf(%{segments: [{id, _name} | _]}), do: segment_leaf(id)
  defp new_leaf(_assigns), do: event_leaf()

  defp attribute_leaf(%Attribute{} = attribute) do
    [op | _] = Conditions.operators(attribute.type)
    %{type: :attribute, id: new_id(), key: attribute.key, op: op, value: default(attribute, op)}
  end

  defp event_leaf, do: %{type: :event, id: new_id(), name: "", op: "happened", within_days: ""}
  defp segment_leaf(segment), do: %{type: :segment, id: new_id(), segment: segment, op: "in"}

  defp default(attribute, op), do: if(kind(attribute, op) == :enum, do: [], else: "")

  @doc false
  # A condition as the builder's tree: always a group at the top.
  def parse(nil), do: new_group("all")

  def parse(condition) when is_map(condition) do
    case to_node(condition) do
      %{type: :group} = group -> group
      leaf -> %{new_group("all") | children: [leaf]}
    end
  end

  def parse(_other), do: new_group("all")

  defp to_node(%{"all" => list} = c) when is_list(list) and map_size(c) == 1,
    do: group("all", list)

  defp to_node(%{"any" => list} = c) when is_list(list) and map_size(c) == 1,
    do: group("any", list)

  defp to_node(%{"not" => %{"any" => list} = inner}) when is_list(list) and map_size(inner) == 1,
    do: group("none", list)

  defp to_node(%{"not" => %{"all" => list} = inner}) when is_list(list) and map_size(inner) == 1,
    do: group("not_all", list)

  defp to_node(%{"not" => other}), do: %{new_group("not_all") | children: [to_node(other)]}

  defp to_node(%{"attribute" => key, "op" => op} = leaf) when is_binary(key) and is_binary(op) do
    %{type: :attribute, id: new_id(), key: key, op: op, value: value_text(leaf["value"])}
  end

  defp to_node(%{"event" => name, "op" => op} = leaf) when is_binary(name) and is_binary(op) do
    %{
      type: :event,
      id: new_id(),
      name: name,
      op: op,
      within_days: value_text(leaf["within_days"])
    }
  end

  defp to_node(%{"segment" => id} = leaf) when is_binary(id) do
    %{type: :segment, id: new_id(), segment: id, op: leaf["op"] || "in"}
  end

  defp to_node(other), do: %{type: :raw, id: new_id(), condition: other}

  defp group(op, list), do: %{new_group(op) | children: Enum.map(list, &to_node/1)}

  defp value_text(nil), do: ""
  defp value_text(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp value_text(value), do: to_string(value)

  @doc false
  # The tree as a condition.
  def to_condition(%{type: :group, op: op, children: children}) do
    list = Enum.map(children, &to_condition/1)

    case op do
      "all" -> %{"all" => list}
      "any" -> %{"any" => list}
      "none" -> %{"not" => %{"any" => list}}
      "not_all" -> %{"not" => %{"all" => list}}
    end
  end

  def to_condition(%{type: :attribute, key: key, op: op, value: value}) do
    case value do
      _ when op in ~w(set not_set true false) -> %{"attribute" => key, "op" => op}
      list when is_list(list) -> %{"attribute" => key, "op" => op, "value" => list}
      text -> %{"attribute" => key, "op" => op, "value" => String.trim(text)}
    end
  end

  def to_condition(%{type: :event, name: name, op: op, within_days: days}) do
    leaf = %{"event" => String.trim(name), "op" => op}
    if String.trim(days) == "", do: leaf, else: Map.put(leaf, "within_days", String.trim(days))
  end

  def to_condition(%{type: :segment, segment: segment, op: op}),
    do: %{"segment" => segment, "op" => op}

  def to_condition(%{type: :raw, condition: condition}), do: condition

  defp empty?(%{type: :group, op: "all", children: []}), do: true
  defp empty?(_tree), do: false

  defp map_node(%{id: id} = node, id, fun), do: fun.(node)

  defp map_node(%{type: :group} = group, id, fun),
    do: %{group | children: Enum.map(group.children, &map_node(&1, id, fun))}

  defp map_node(node, _id, _fun), do: node

  defp remove(%{type: :group} = group, id) do
    children = for child <- group.children, child.id != id, do: remove(child, id)
    %{group | children: children}
  end

  defp remove(node, _id), do: node

  # How deep a group is: the top one is 1.
  defp depth_of(tree, id), do: depth_of(tree, id, 1) || @max_depth

  defp depth_of(%{id: id}, id, depth), do: depth

  defp depth_of(%{type: :group, children: children}, id, depth),
    do: Enum.find_value(children, &depth_of(&1, id, depth + 1))

  defp depth_of(_node, _id, _depth), do: nil

  # The form's values, by node id, into the tree.
  defp put_params(%{type: :group} = group, params, attributes) do
    op =
      case params[group.id] do
        %{"op" => op} when op in ["all", "any", "none", "not_all"] -> op
        _ -> group.op
      end

    %{group | op: op, children: Enum.map(group.children, &put_params(&1, params, attributes))}
  end

  defp put_params(%{id: id} = leaf, params, attributes) do
    case params[id] do
      %{} = values -> put_leaf(leaf, values, attributes)
      _ -> leaf
    end
  end

  defp put_leaf(leaf, %{"subject" => "attribute:" <> key} = values, attributes) do
    case {leaf, Enum.find(attributes, &(&1.key == key))} do
      {_leaf, nil} ->
        leaf

      {%{type: :attribute, key: ^key}, attribute} ->
        attribute_values(leaf, values, attribute)

      {_leaf, attribute} ->
        put_leaf(%{attribute_leaf(attribute) | id: leaf.id}, values, attributes)
    end
  end

  defp put_leaf(%{type: :event} = leaf, %{"subject" => "event"} = values, _attributes) do
    %{
      leaf
      | name: text(values["name"]),
        op: one_of(values["op"], Conditions.event_operators(), leaf.op),
        within_days: text(values["within_days"])
    }
  end

  defp put_leaf(leaf, %{"subject" => "event"} = values, attributes),
    do: put_leaf(%{event_leaf() | id: leaf.id}, values, attributes)

  defp put_leaf(%{type: :segment} = leaf, %{"subject" => "segment"} = values, _attributes) do
    %{leaf | segment: text(values["segment"]), op: one_of(values["op"], ~w(in not_in), leaf.op)}
  end

  defp put_leaf(leaf, %{"subject" => "segment"} = values, attributes),
    do: put_leaf(%{segment_leaf("") | id: leaf.id}, values, attributes)

  defp put_leaf(leaf, _values, _attributes), do: leaf

  defp attribute_values(leaf, values, %Attribute{} = attribute) do
    op =
      if Attribute.type_name(attribute) == :boolean,
        do: boolean_op(values["checked"], leaf.op),
        else: one_of(values["op"], Conditions.operators(attribute.type), leaf.op)

    value =
      cond do
        kind(attribute, op) != kind(attribute, leaf.op) ->
          default(attribute, op)

        kind(attribute, op) == :enum ->
          values |> Map.get("value", []) |> List.wrap() |> Enum.reject(&(&1 == ""))

        true ->
          text(values["value"])
      end

    %{leaf | op: op, value: value}
  end

  defp boolean_op("true", _op), do: "true"
  defp boolean_op("false", _op), do: "false"
  defp boolean_op(_checked, op), do: op

  defp one_of(value, allowed, fallback), do: if(value in allowed, do: value, else: fallback)

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""

  # What an attribute's operator takes as its value.
  defp kind(_attribute, op) when op in ~w(set not_set true false), do: :none

  defp kind(%Attribute{} = attribute, op) do
    case Attribute.type_name(attribute) do
      :string ->
        :text

      :integer ->
        :number

      :boolean ->
        :none

      :enum ->
        :enum

      type when type in [:date, :datetime] and op in ~w(more_than_days_ago less_than_days_ago) ->
        :days

      type when type in [:date, :datetime] ->
        :date
    end
  end

  # ── Rendering ───────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="ta-conditions" id={@id}>
      <form id={"#{@id}-form"} phx-change="change" phx-submit="change" phx-target={@myself}>
        <fieldset class="ta-conditions-fieldset" disabled={@read_only}>
          <legend class="ta-label">{@label}</legend>
          <p :if={@hint} class="ta-hint">{@hint}</p>
          <.group
            group={@tree}
            depth={1}
            builder={@id}
            myself={@myself}
            attributes={@attributes}
            events={@events}
            events?={@events?}
            segments={@segments}
            read_only={@read_only}
          />
        </fieldset>
        <datalist :if={@events?} id={"#{@id}-events"}>
          <option :for={{name, label} <- @events} value={name}>{label}</option>
        </datalist>
      </form>

      <div class="ta-conditions-result" aria-live="polite">
        <p :if={@sentence} class="ta-conditions-sentence">{@sentence}</p>
        <ul :if={@errors != []} class="ta-conditions-errors">
          <li :for={error <- @errors} class="ta-error">{error}</li>
        </ul>
        <p :if={@count != :none and @errors == []} class="ta-conditions-count">
          <.icon name="users" />
          <span :if={@counting and @counted == nil}>Counting…</span>
          <span :if={@counted == :error}>The people could not be counted.</span>
          <span :if={is_map(@counted)}>{people(@counted.count)}{if @counting, do: " …"}</span>
        </p>
        <ul :if={@count == :sample and is_map(@counted) and @counted.sample not in [nil, []] and @errors == []} class="ta-people" aria-label="The first people">
          <li :for={person <- @counted.sample}>
            <span class="ta-people-name">{person.name || person.email || person.id}</span>
            <span :if={person.name && person.email} class="ta-hint">{person.email}</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :group, :map, required: true
  attr :depth, :integer, required: true
  attr :builder, :string, required: true
  attr :myself, :any, required: true
  attr :attributes, :list, required: true
  attr :events, :list, required: true
  attr :events?, :boolean, required: true
  attr :segments, :list, required: true
  attr :read_only, :boolean, required: true

  defp group(assigns) do
    assigns = assign(assigns, :field, "#{assigns.builder}-#{assigns.group.id}")

    ~H"""
    <div class={["ta-cond-group", @depth > 1 && "ta-cond-subgroup"]} role="group" aria-labelledby={"#{@field}-op-label"}>
      <div class="ta-cond-head">
        <label id={"#{@field}-op-label"} for={"#{@field}-op"} class="ta-visually-hidden">
          {if @depth == 1, do: "Match", else: "Match, in this group"}
        </label>
        <select id={"#{@field}-op"} name={"n[#{@group.id}][op]"} class="ta-input ta-cond-op">
          <option :for={{value, label} <- group_ops()} value={value} selected={value == @group.op}>
            {label}
          </option>
        </select>
        <button
          :if={@depth > 1 and not @read_only}
          type="button"
          class="ta-icon-button ta-push"
          phx-click="remove"
          phx-value-node={@group.id}
          phx-target={@myself}
          aria-label="Remove this group"
        >
          <.icon name="trash-2" />
        </button>
      </div>

      <p :if={@group.children == []} class="ta-hint ta-cond-none">
        No rule: {if @group.op in ["all", "not_all"], do: "everyone", else: "no one"}.
      </p>

      <ol :if={@group.children != []} class="ta-cond-list">
        <li :for={{child, index} <- Enum.with_index(@group.children, 1)}>
          <.group
            :if={child.type == :group}
            group={child}
            depth={@depth + 1}
            builder={@builder}
            myself={@myself}
            attributes={@attributes}
            events={@events}
            events?={@events?}
            segments={@segments}
            read_only={@read_only}
          />
          <.rule
            :if={child.type != :group}
            rule={child}
            index={index}
            builder={@builder}
            myself={@myself}
            attributes={@attributes}
            events?={@events?}
            segments={@segments}
            read_only={@read_only}
          />
        </li>
      </ol>

      <div :if={not @read_only} class="ta-cond-add">
        <button
          type="button"
          class="ta-button ta-small ta-quiet"
          phx-click="add_rule"
          phx-value-group={@group.id}
          phx-target={@myself}
        >
          <.icon name="plus" />Add a rule
        </button>
        <button
          :if={@depth < max_depth()}
          type="button"
          class="ta-button ta-small ta-quiet"
          phx-click="add_group"
          phx-value-group={@group.id}
          phx-target={@myself}
        >
          <.icon name="list" />Add a group
        </button>
      </div>
    </div>
    """
  end

  attr :rule, :map, required: true
  attr :index, :integer, required: true
  attr :builder, :string, required: true
  attr :myself, :any, required: true
  attr :attributes, :list, required: true
  attr :events?, :boolean, required: true
  attr :segments, :list, required: true
  attr :read_only, :boolean, required: true

  defp rule(assigns) do
    rule = assigns.rule

    attribute =
      if rule.type == :attribute, do: Enum.find(assigns.attributes, &(&1.key == rule.key))

    assigns =
      assign(assigns,
        field: "#{assigns.builder}-#{rule.id}",
        name: "n[#{rule.id}]",
        attribute: attribute,
        kind: attribute && kind(attribute, rule.op)
      )

    ~H"""
    <div class="ta-rule" role="group" aria-label={"Rule #{@index}"}>
      <%= if @rule.type == :raw do %>
        <p class="ta-hint ta-rule-raw">
          A rule this page cannot show, kept as it is: <code>{JSON.encode!(@rule.condition)}</code>
        </p>
      <% else %>
        <label for={"#{@field}-subject"} class="ta-visually-hidden">What the rule tests</label>
        <select id={"#{@field}-subject"} name={"#{@name}[subject]"} class="ta-input ta-rule-subject">
          <optgroup :if={@attributes != []} label="About the person">
            <option
              :for={attribute <- @attributes}
              value={"attribute:#{attribute.key}"}
              selected={@rule.type == :attribute and @rule.key == attribute.key}
            >
              {attribute.label}
            </option>
          </optgroup>
          <option :if={@rule.type == :attribute and @attribute == nil} value={"attribute:#{@rule.key}"} selected>
            {@rule.key} (no longer known)
          </option>
          <option :if={@events? or @rule.type == :event} value="event" selected={@rule.type == :event}>
            An event
          </option>
          <option :if={@segments != [] or @rule.type == :segment} value="segment" selected={@rule.type == :segment}>
            A segment
          </option>
        </select>

        <.attribute_rule
          :if={@rule.type == :attribute and @attribute}
          rule={@rule}
          field={@field}
          name={@name}
          attribute={@attribute}
          kind={@kind}
        />
        <.event_rule
          :if={@rule.type == :event}
          rule={@rule}
          field={@field}
          name={@name}
          builder={@builder}
        />
        <.segment_rule
          :if={@rule.type == :segment}
          rule={@rule}
          field={@field}
          name={@name}
          segments={@segments}
        />
      <% end %>

      <button
        :if={not @read_only}
        type="button"
        class="ta-icon-button ta-rule-remove"
        phx-click="remove"
        phx-value-node={@rule.id}
        phx-target={@myself}
        aria-label={"Remove rule #{@index}"}
      >
        <.icon name="x" />
      </button>
    </div>
    """
  end

  defp attribute_rule(%{kind: kind, attribute: attribute} = assigns) do
    assigns =
      assign(assigns,
        boolean: Attribute.type_name(attribute) == :boolean,
        operators: Conditions.operators(attribute.type),
        enum: (kind == :enum && elem(attribute.type, 1)) || [],
        kind: kind
      )

    ~H"""
    <%= if @boolean do %>
      <input type="hidden" name={"#{@name}[checked]"} value="false" />
      <label class="ta-check ta-rule-check">
        <input type="checkbox" name={"#{@name}[checked]"} value="true" checked={@rule.op == "true"} />
        Yes <span class="ta-visually-hidden">, {@attribute.label}</span>
      </label>
    <% else %>
      <label for={"#{@field}-op"} class="ta-visually-hidden">How {@attribute.label} compares</label>
      <select id={"#{@field}-op"} name={"#{@name}[op]"} class="ta-input ta-rule-op">
        <option :for={op <- @operators} value={op} selected={op == @rule.op}>{op_label(op)}</option>
      </select>
      <.rule_value
        kind={@kind}
        field={@field}
        name={@name}
        rule={@rule}
        attribute={@attribute}
        enum={@enum}
      />
    <% end %>
    """
  end

  defp rule_value(%{kind: :none} = assigns), do: ~H""

  defp rule_value(%{kind: :enum} = assigns) do
    ~H"""
    <fieldset class="ta-rule-picks">
      <legend class="ta-visually-hidden">{@attribute.label}: one of</legend>
      <input type="hidden" name={"#{@name}[value][]"} value="" />
      <label :for={{value, label} <- @enum} class="ta-rule-pick">
        <input type="checkbox" name={"#{@name}[value][]"} value={value} checked={value in List.wrap(@rule.value)} />
        {label}
      </label>
    </fieldset>
    """
  end

  defp rule_value(assigns) do
    assigns =
      assign(assigns,
        type:
          case assigns.kind do
            :date -> "date"
            :text -> "text"
            _number -> "number"
          end,
        value:
          if(assigns.kind == :date,
            do: String.slice(assigns.rule.value, 0, 10),
            else: assigns.rule.value
          )
      )

    ~H"""
    <label for={"#{@field}-value"} class="ta-visually-hidden">
      {if @kind == :days, do: "Days", else: "Value"}
    </label>
    <input
      type={@type}
      id={"#{@field}-value"}
      name={"#{@name}[value]"}
      value={@value}
      class={["ta-input ta-rule-value", @kind in [:days, :number] && "ta-rule-number"]}
      min={if @kind == :days, do: "1"}
      step={if @kind in [:days, :number], do: "1"}
      maxlength={if @kind == :text, do: "255"}
      phx-debounce="300"
      autocomplete="off"
    />
    <span :if={@kind == :days} class="ta-rule-unit">days ago</span>
    """
  end

  defp event_rule(assigns) do
    ~H"""
    <label for={"#{@field}-name"} class="ta-visually-hidden">The event's name</label>
    <input
      type="text"
      id={"#{@field}-name"}
      name={"#{@name}[name]"}
      value={@rule.name}
      list={"#{@builder}-events"}
      class="ta-input ta-rule-value"
      placeholder="signed_up"
      maxlength="64"
      phx-debounce="300"
      autocomplete="off"
    />
    <label for={"#{@field}-op"} class="ta-visually-hidden">Happened or not</label>
    <select id={"#{@field}-op"} name={"#{@name}[op]"} class="ta-input ta-rule-op">
      <option :for={op <- Conditions.event_operators()} value={op} selected={op == @rule.op}>
        {op_label(op)}
      </option>
    </select>
    <span class="ta-rule-unit">in the last</span>
    <label for={"#{@field}-days"} class="ta-visually-hidden">Days, or empty for ever</label>
    <input
      type="number"
      id={"#{@field}-days"}
      name={"#{@name}[within_days]"}
      value={@rule.within_days}
      min="1"
      step="1"
      class="ta-input ta-rule-value ta-rule-number"
      placeholder="any"
      phx-debounce="300"
    />
    <span class="ta-rule-unit">days</span>
    """
  end

  defp segment_rule(assigns) do
    ~H"""
    <label for={"#{@field}-op"} class="ta-visually-hidden">In or not in</label>
    <select id={"#{@field}-op"} name={"#{@name}[op]"} class="ta-input ta-rule-op">
      <option value="in" selected={@rule.op == "in"}>is in</option>
      <option value="not_in" selected={@rule.op == "not_in"}>is not in</option>
    </select>
    <label for={"#{@field}-segment"} class="ta-visually-hidden">The segment</label>
    <select id={"#{@field}-segment"} name={"#{@name}[segment]"} class="ta-input ta-rule-value">
      <option :if={not Enum.any?(@segments, &(elem(&1, 0) == @rule.segment))} value={@rule.segment} selected>
        {if @rule.segment == "", do: "Choose a segment", else: "A segment that no longer exists"}
      </option>
      <option :for={{id, name} <- @segments} value={id} selected={id == @rule.segment}>{name}</option>
    </select>
    """
  end

  defp group_ops, do: @group_ops
  defp op_label(op), do: Map.get(@op_labels, op, op)

  @doc false
  def people(1), do: "1 person"
  def people(n), do: "#{delimit(n)} people"

  @doc false
  def delimit(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
