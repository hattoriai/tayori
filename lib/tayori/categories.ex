defmodule Tayori.Categories do
  @moduledoc """
  The categories of the news (`Tayori.Category`), in their order. The
  admin manages them; a script or a seed can too:

      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "New"}, "color" => "blue"})
  """

  import Ecto.Query

  alias Tayori.{Category, Config, Entry}

  @doc "The categories, in their order."
  @spec list() :: [Category.t()]
  def list do
    config = Config.get()

    from(c in Category, order_by: [asc: c.position, asc: c.key])
    |> config.repo.all(prefix: config.prefix)
  end

  @doc "The categories by key, for rendering entries."
  @spec by_key() :: %{String.t() => Category.t()}
  def by_key, do: Map.new(list(), &{&1.key, &1})

  @doc "A category by its key, or nil."
  @spec get(String.t()) :: Category.t() | nil
  def get(key) when is_binary(key) do
    config = Config.get()
    config.repo.get(Category, key, prefix: config.prefix)
  end

  @doc "A changeset of a category, for a form."
  @spec change(Category.t(), map()) :: Ecto.Changeset.t()
  def change(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs, Config.get().locales)
  end

  @doc "Creates a category, at the end of the list."
  @spec create(map()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    config = Config.get()

    position =
      config.repo.one(from(c in Category, select: max(c.position)), prefix: config.prefix) || -1

    %Category{position: position + 1}
    |> change(attrs)
    |> config.repo.insert(prefix: config.prefix)
    |> changed()
  end

  @doc "Updates a category's names and colour. Its key stays."
  @spec update(Category.t(), map()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def update(%Category{} = category, attrs) do
    config = Config.get()

    category
    |> change(Map.drop(attrs, ["key", :key]))
    |> config.repo.update(prefix: config.prefix)
    |> changed()
  end

  @doc """
  Deletes a category, and takes it off the entries that have it.
  """
  @spec delete(Category.t()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Category{key: key} = category) do
    config = Config.get()

    config.repo.transact(
      fn ->
        entries =
          from(e in Entry, select: [:id, :categories])
          |> config.repo.all(prefix: config.prefix)
          |> Enum.filter(&(key in &1.categories))

        for entry <- entries do
          entry
          |> Ecto.Changeset.change(categories: List.delete(entry.categories, key))
          |> config.repo.update!(prefix: config.prefix)
        end

        config.repo.delete(category, prefix: config.prefix)
      end,
      []
    )
    |> changed()
  end

  @doc "Puts the categories in the order of the keys given."
  @spec reorder([String.t()]) :: :ok
  def reorder(keys) when is_list(keys) do
    config = Config.get()

    config.repo.transact(
      fn ->
        keys
        |> Enum.with_index()
        |> Enum.each(fn {key, position} ->
          from(c in Category, where: c.key == ^key)
          |> config.repo.update_all([set: [position: position]], prefix: config.prefix)
        end)

        {:ok, :ok}
      end,
      []
    )

    Tayori.broadcast({Tayori, :categories, nil})
    :ok
  end

  defp changed({:ok, category}) do
    Tayori.broadcast({Tayori, :categories, category.key})
    {:ok, category}
  end

  defp changed(error), do: error
end
