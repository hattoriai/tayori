defmodule Tayori.CategoriesTest do
  use TayoriTest.DataCase

  alias Tayori.{Categories, Category}

  for_each_repo do
    test "a new category takes its key from its name, at the end of the list" do
      {:ok, new} = Categories.create(%{"names" => %{"en" => "New"}, "color" => "blue"})
      {:ok, fixed} = Categories.create(%{"names" => %{"en" => "Bug fixes!"}})

      assert new.key == "new"
      assert fixed.key == "bug-fixes"
      assert fixed.color == "gray"
      assert Enum.map(Categories.list(), & &1.key) == ["new", "bug-fixes"]
      assert new.position < fixed.position
    end

    test "a key given is kept, and must be a slug" do
      {:ok, category} =
        Categories.create(%{"key" => "shipped", "names" => %{"en" => "New"}, "color" => "green"})

      assert category.key == "shipped"

      assert {:error, changeset} =
               Categories.create(%{"key" => "Not A Key", "names" => %{"en" => "Other"}})

      assert "use lowercase letters, digits and dashes" in errors_on(changeset).key
    end

    test "the names: the first language is needed, the others trimmed and kept to the locales" do
      assert {:error, changeset} = Categories.create(%{"names" => %{"pt-PT" => "Novo"}})
      assert "needs the en name" in errors_on(changeset).names

      {:ok, category} =
        Categories.create(%{
          "names" => %{"en" => "  New  ", "pt-PT" => " ", "fr" => "Nouveau"},
          "color" => "blue"
        })

      assert category.names == %{"en" => "New"}
    end

    test "a name in the reader's language, else in the first, else the key" do
      {:ok, category} =
        Categories.create(%{"names" => %{"en" => "New", "pt-PT" => "Novo"}, "color" => "blue"})

      locales = ["en", "pt-PT"]
      assert Category.name(category, "pt-PT", locales) == "Novo"
      assert Category.name(category, "en", locales) == "New"
      assert Category.name(category, "de", locales) == "New"
      assert Category.name(category, nil, locales) == "New"

      assert Category.name(%Category{key: "odd", names: %{"pt-PT" => "Ímpar"}}, "en", locales) ==
               "Ímpar"

      assert Category.name(%Category{key: "odd", names: %{}}, "en", locales) == "odd"
    end

    test "the colour is one of the themes'" do
      assert {:error, changeset} =
               Categories.create(%{"names" => %{"en" => "New"}, "color" => "chartreuse"})

      assert "is invalid" in errors_on(changeset).color

      for color <- Category.colors() do
        assert {:ok, _} =
                 Categories.create(%{"names" => %{"en" => "C #{color}"}, "color" => color})
      end
    end

    test "two categories cannot have the same key" do
      {:ok, _} = Categories.create(%{"names" => %{"en" => "New"}})
      assert {:error, changeset} = Categories.create(%{"names" => %{"en" => "New"}})
      assert "is the key of another category" in errors_on(changeset).key
      assert length(Categories.list()) == 1
    end

    test "an update changes the names and the colour, never the key" do
      {:ok, category} = Categories.create(%{"names" => %{"en" => "New"}, "color" => "blue"})

      {:ok, updated} =
        Categories.update(category, %{
          "key" => "other",
          "names" => %{"en" => "Shiny", "pt-PT" => "Brilhante"},
          "color" => "pink"
        })

      assert updated.key == "new"
      assert updated.names == %{"en" => "Shiny", "pt-PT" => "Brilhante"}
      assert updated.color == "pink"
      assert Categories.get("new").color == "pink"
      assert Categories.get("other") == nil

      assert {:error, changeset} = Categories.update(updated, %{"color" => "neon"})
      assert "is invalid" in errors_on(changeset).color
    end

    test "reorder puts the categories in the order given" do
      for name <- ~w(New Improved Fixed),
          do: {:ok, _} = Categories.create(%{"names" => %{"en" => name}})

      :ok = Categories.reorder(["fixed", "new", "improved"])
      assert Enum.map(Categories.list(), & &1.key) == ["fixed", "new", "improved"]
      assert Map.keys(Categories.by_key()) |> Enum.sort() == ["fixed", "improved", "new"]
    end

    test "deleting a category takes it off the entries that have it" do
      {:ok, new} = Categories.create(%{"names" => %{"en" => "New"}})
      {:ok, _} = Categories.create(%{"names" => %{"en" => "Fixed"}})
      both = entry!("Both", %{categories: ["new", "fixed"]})
      only = entry!("Only new", %{categories: ["new"]})
      other = entry!("Other", %{categories: ["fixed"]})

      {:ok, _} = Categories.delete(new)

      assert Categories.get("new") == nil
      assert Entries.get!(both.id).categories == ["fixed"]
      assert Entries.get!(only.id).categories == []
      assert Entries.get!(other.id).categories == ["fixed"]
    end

    test "every change is told on the PubSub" do
      :ok = Tayori.subscribe()

      {:ok, category} = Categories.create(%{"names" => %{"en" => "New"}})
      assert_receive {Tayori, :categories, "new"}

      {:ok, category} = Categories.update(category, %{"color" => "red"})
      assert_receive {Tayori, :categories, "new"}

      :ok = Categories.reorder(["new"])
      assert_receive {Tayori, :categories, nil}

      {:ok, _} = Categories.delete(category)
      assert_receive {Tayori, :categories, "new"}

      {:error, _} = Categories.create(%{"names" => %{}})
      refute_receive {Tayori, :categories, _}, 50
    end
  end
end
