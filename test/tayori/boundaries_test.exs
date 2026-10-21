defmodule Tayori.BoundariesTest do
  # The two modules of Tayori, the changelog and the campaigns, each
  # depend on the core and never on each other: either one may be off,
  # and either one may change, without the other knowing.
  #
  # The test reads what each compiled module refers to from its BEAM
  # file: the abstract code of its debug info (which Mix keeps in the
  # test build), walked whole, gives every module name the code holds as
  # an atom. That is the remote calls (which the :imports chunk would give
  # too), and also what that chunk misses: structs built and matched
  # (%Entry{}), modules passed as values (a tool in a list, a behaviour's
  # module in a map), and module attributes kept in the code. Names in
  # docs and strings are not code, and do not count.
  #
  # The core is everything else, and may refer to both: Tayori itself and
  # Tayori.Config (the modules on), Tayori.Router (the mounts),
  # Tayori.Jobs, Tayori.Worker and Tayori.Scheduler (the work of both),
  # Tayori.MCP (the server, with both tool lists), Tayori.MCP.Access and
  # Tayori.MCP.Support (shared helpers of the tools), Tayori.Admin.Layouts,
  # Tayori.Admin.Components and Tayori.Admin.SettingsLive (the admin's
  # frame and settings), Tayori.Messages, Tayori.Mail.Layout, Tayori.Test
  # and Tayori.Migrations (the tables of both).
  use ExUnit.Case, async: true

  # Modules by name: a name alone is that module, a name with ".*" the
  # module and those under it.
  @campaigns ~w(
    Tayori.Campaigns.*
    Tayori.Audience.*
    Tayori.Conditions
    Tayori.Recipient
    Tayori.MCP.Campaigns
    Tayori.MCP.Tools.Campaigns.*
    Tayori.Admin.AudienceLive
    Tayori.Admin.CampaignLive
    Tayori.Admin.CampaignsLive
    Tayori.Admin.SegmentLive
    Tayori.Admin.ConditionBuilder
    Tayori.Router.Mail
  )

  @changelog ~w(
    Tayori.Entries
    Tayori.Entry.*
    Tayori.Inbox
    Tayori.Ingest
    Tayori.Digest
    Tayori.Subscribers
    Tayori.Page
    Tayori.API.*
    Tayori.Router.API
    Tayori.Router.Page
    Tayori.Live.*
    Tayori.Panel.*
    Tayori.Categories
    Tayori.Category
    Tayori.Reactions
    Tayori.Reaction
    Tayori.Views
    Tayori.View
    Tayori.Dismissal
    Tayori.Announcements
    Tayori.Change
    Tayori.Source
    Tayori.Sources.*
    Tayori.Webhooks
    Tayori.GitHub
    Tayori.Admin.EntriesLive
    Tayori.Admin.EntryLive
    Tayori.Admin.InboxLive
    Tayori.Admin.CategoriesLive
    Tayori.Admin.Writer
  )

  # The changelog's MCP tools: every tool that is not a campaign's.
  @changelog_tools "Tayori.MCP.Tools."

  test "the campaigns refer to nothing of the changelog" do
    assert violations(&campaigns?/1, &changelog?/1) == []
  end

  test "the changelog refers to nothing of the campaigns" do
    assert violations(&changelog?/1, &campaigns?/1) == []
  end

  test "the groups name modules that exist, and the test reads them" do
    modules = modules()

    for pattern <- @campaigns ++ @changelog do
      assert Enum.any?(modules, &matches?(&1, pattern)), "no module is #{pattern}"
    end

    # A struct matched, not called: the walk sees it.
    assert Tayori.Campaigns.Letter in references(Tayori.Campaigns.Letters)

    # The core names both: the server lists the tools of each.
    mcp = references(Tayori.MCP)
    assert Enum.any?(mcp, &changelog?/1) and Enum.any?(mcp, &campaigns?/1)
    assert Enum.count(modules, &campaigns?/1) > 20
    assert Enum.count(modules, &changelog?/1) > 20
  end

  # Each module of one side, with the modules of the other it names.
  defp violations(side?, other?) do
    for module <- modules(),
        side?.(module),
        names = Enum.filter(references(module), other?),
        names != [] do
      {module, names}
    end
  end

  defp modules do
    {:ok, modules} = :application.get_key(:tayori, :modules)
    Enum.filter(modules, &String.starts_with?(Atom.to_string(&1), "Elixir.Tayori."))
  end

  defp references(module) do
    path = :code.which(module)

    {:ok, {^module, [abstract_code: {:raw_abstract_v1, forms}]}} =
      :beam_lib.chunks(path, [:abstract_code])

    forms
    |> atoms(MapSet.new())
    |> Enum.filter(&(&1 != module and String.starts_with?(Atom.to_string(&1), "Elixir.")))
  end

  defp atoms(term, acc) when is_atom(term), do: MapSet.put(acc, term)
  defp atoms(term, acc) when is_tuple(term), do: atoms(Tuple.to_list(term), acc)
  defp atoms([head | tail], acc), do: atoms(tail, atoms(head, acc))
  defp atoms(term, acc) when is_map(term), do: atoms(Map.to_list(term), acc)
  defp atoms(_term, acc), do: acc

  defp campaigns?(module), do: Enum.any?(@campaigns, &matches?(module, &1))

  defp changelog?(module) do
    name = inspect(module)

    Enum.any?(@changelog, &matches?(module, &1)) or
      (String.starts_with?(name, @changelog_tools) and not campaigns?(module))
  end

  defp matches?(module, pattern) do
    name = inspect(module)

    case String.split(pattern, ".*") do
      [prefix, ""] -> name == prefix or String.starts_with?(name, prefix <> ".")
      [exact] -> name == exact
    end
  end
end
