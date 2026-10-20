defmodule TayoriTest.DataCase do
  @moduledoc """
  Tests on the database, run once on SQLite and once on PostgreSQL (when
  it is reachable): `use TayoriTest.DataCase` and write the tests in
  `for_each_repo do ... end`.

  The config of Tayori is one for the node, so these tests are not async.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import TayoriTest.DataCase
      alias Tayori.{Entries, Entry, Reader}
    end
  end

  @doc """
  Defines the tests of the block once for each repo, in a describe of its
  own, tagged :postgres for PostgreSQL.
  """
  defmacro for_each_repo(do: block) do
    for {name, repo, tags} <- [
          {"SQLite", TayoriTest.SQLiteRepo, []},
          {"PostgreSQL", TayoriTest.PostgresRepo, [postgres: true]}
        ] do
      quote do
        describe unquote(name) do
          @describetag unquote(tags)
          setup do: TayoriTest.DataCase.checkout(unquote(repo))
          unquote(block)
        end
      end
    end
  end

  @doc false
  def checkout(repo, opts \\ []) do
    pid = Sandbox.start_owner!(repo, shared: true)
    ExUnit.Callbacks.on_exit(fn -> Sandbox.stop_owner(pid) end)

    config =
      Tayori.Config.new(
        Keyword.merge(
          [
            repo: repo,
            pubsub: TayoriTest.PubSub,
            locales: ["en", "pt-PT"],
            secret_key_base: String.duplicate("tayori-test-secret-", 4)
          ],
          opts
        )
      )

    Tayori.Config.put(config)
    {:ok, repo: repo, config: config}
  end

  @doc "Creates an entry with an English title, published at a time (or a draft)."
  def entry!(title, attrs \\ %{}) do
    {published_at, attrs} = Map.pop(attrs, :published_at)

    {:ok, entry} =
      attrs
      |> Map.put_new(:translations, [
        %{locale: "en", title: title, body: Kotoba.Content.from_markdown("About #{title}.")}
      ])
      |> Tayori.Entries.create()

    if published_at do
      {:ok, entry} = Tayori.Entries.publish(entry, published_at)
      entry
    else
      entry
    end
  end

  @doc "A time some minutes from now (negative for the past)."
  def minutes(n), do: DateTime.add(DateTime.utc_now(), n * 60, :second)

  @doc "The errors of a changeset, by field, as their messages."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc "Puts the config of the test with these options changed, and returns it."
  def put_config(%Tayori.Config{} = config, changes) do
    changes = Enum.map(changes, fn {key, value} -> {key, Tayori.Config.option(key, value)} end)
    config = struct!(config, changes)
    Tayori.Config.put(config)
    config
  end
end
