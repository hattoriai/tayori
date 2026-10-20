defmodule Tayori.AITest do
  use TayoriTest.ConnCase

  import Ecto.Query

  alias Tayori.{AI, Settings}
  alias TayoriTest.FakeAI

  doctest Tayori.AI

  defp configure(model \\ "anthropic:claude-sonnet-5-5", key \\ "sk-test-123") do
    :ok = AI.save_settings(%{"model" => model, "about" => "Atelier, a studio's projects."}, key)
  end

  describe "settings" do
    test "the key is encrypted, kept, replaced and removed" do
      refute AI.configured?()
      configure()

      assert AI.configured?()

      assert AI.settings() == %{
               model: "anthropic:claude-sonnet-5-5",
               about: "Atelier, a studio's projects.",
               key?: true
             }

      assert Settings.secret("ai") == "sk-test-123"

      stored =
        TayoriTest.SQLiteRepo.one!(from(s in "tayori_settings", select: s.secret))

      refute stored =~ "sk-test-123"

      :ok = AI.save_settings(%{"model" => "openai:gpt-5"})
      assert Settings.secret("ai") == "sk-test-123"

      :ok = AI.save_settings(%{"model" => "openai:gpt-5"}, nil)
      refute AI.configured?()
    end

    test "the app's Cloak vault encrypts the key, before the secret_key_base", %{config: config} do
      Tayori.Config.put(%{config | vault: TayoriTest.Vault})
      configure()

      stored = TayoriTest.SQLiteRepo.one!(from(s in "tayori_settings", select: s.secret))
      assert stored == "vault:" <> Base.encode64(String.reverse("sk-test-123"))
      assert Settings.secret("ai") == "sk-test-123"
      assert AI.configured?()

      # A vault alone is enough.
      Tayori.Config.put(%{config | vault: TayoriTest.Vault, secret_key_base: nil})
      assert AI.available?()
      assert Settings.secret("ai") == "sk-test-123"

      # A key the vault cannot read is no key.
      Tayori.Config.put(config)
      assert Settings.secret("ai") == nil
    end

    test "with no vault and no secret_key_base, there is no AI", %{config: config} do
      Tayori.Config.put(%{config | secret_key_base: nil})
      refute AI.available?()
      assert AI.stream({:assist, "fix", "Hi", "en"}) == {:error, :not_configured}
    end

    test "the page saves the model and the key, and never shows the key", %{conn: conn} do
      {:ok, view, html} = conn |> as_admin() |> live("/admin/news/settings")
      assert html =~ "Writing with AI"

      html =
        view
        |> form("#ai-form",
          ai: %{model: "anthropic:claude-sonnet-5-5", key: "sk-secret", about: "A tool."}
        )
        |> render_submit()

      assert html =~ "The settings are saved."
      assert html =~ "A key is saved"
      refute html =~ "sk-secret"
      assert Settings.secret("ai") == "sk-secret"

      FakeAI.answer(["Hello."])
      view |> element("button", "Check the connection") |> render_click()
      assert render_async(view) =~ "The model answers."
    end
  end

  describe "prompts" do
    test "a draft carries the notes, the language and what the product is" do
      configure()
      FakeAI.answer(["TITLE: x\n---\n"])
      {:ok, stream} = AI.stream({:draft, "- Export button", "pt-PT"})
      assert Enum.join(stream) == "TITLE: x\n---\n"

      assert_received {:asked,
                       %{
                         model: "anthropic:claude-sonnet-5-5",
                         key: "sk-test-123",
                         system: system,
                         prompt: prompt
                       }}

      assert system =~ "Português (Portugal) (pt-PT)"
      assert system =~ "Atelier, a studio's projects."
      assert prompt =~ "- Export button"
    end

    test "complete waits for the whole text, for so long" do
      assert AI.complete({:assist, "fix", "Hi", "en"}) == {:error, :not_configured}

      configure()
      FakeAI.answer(["TITLE: Ex", "ports\n---\n", "Zip it."])
      assert AI.complete({:draft, "- export", "en"}) == {:ok, "TITLE: Exports\n---\nZip it."}

      FakeAI.answer(Stream.map(["a", "b"], fn chunk -> Process.sleep(200) && chunk end))
      assert AI.complete({:assist, "fix", "Hi", "en"}, timeout: 50) == {:error, :timeout}

      FakeAI.answer(Stream.map(["a"], fn _ -> raise "the connection closed" end))
      assert AI.complete({:assist, "fix", "Hi", "en"}) == {:error, "the connection closed"}
    end

    test "an unknown action is refused" do
      configure()
      assert AI.stream({:assist, "nope", "text", "en"}) == {:error, :unknown_action}
    end
  end

  describe "the editor" do
    setup %{conn: conn} do
      configure()
      {:ok, conn: as_admin(conn)}
    end

    test "drafts from notes: the title and summary in the form, the body in the editor", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/admin/news/new")
      view |> element("button", "Write with AI") |> render_click()

      FakeAI.answer([
        "TITLE: Exports in ",
        "two clicks\nSUMMARY: Zip a project.\n",
        "---\nEvery project ",
        "has **Export**."
      ])

      view |> form("#ai-draft", notes: "- export button\n- zip") |> render_submit()

      assert_push_event(view, "kotoba:stream", %{
        id: "tayori-body-en",
        op: "start",
        ref: ref,
        label: "Draft"
      })

      assert_push_event(view, "kotoba:stream", %{
        op: "chunk",
        ref: ^ref,
        text: "Every project has **Export**."
      })

      assert_push_event(view, "kotoba:stream", %{op: "end", ref: ^ref})

      html = render(view)
      assert html =~ ~s(value="Exports in two clicks")
      assert html =~ "Zip a project."
      assert_received {:asked, %{prompt: prompt}}
      assert prompt =~ "- export button"
    end

    test "translates the first language into another", %{conn: conn} do
      entry =
        entry!("Exports", %{
          translations: [
            %{
              locale: "en",
              title: "Exports",
              body: Kotoba.Content.from_markdown("Every **project**.")
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/admin/news/#{entry.id}")
      view |> element(".ta-add-language", "Português (Portugal)") |> render_click()
      view |> element("button", "Write with AI") |> render_click()

      FakeAI.answer(["TITLE: Exportações\nSUMMARY: \n---\nCada **projeto**."])
      view |> element("button", "Translate from English") |> render_click()

      assert_push_event(view, "kotoba:stream", %{
        id: "tayori-body-pt-PT",
        op: "start",
        label: "Translation"
      })

      assert_push_event(view, "kotoba:stream", %{op: "chunk", text: "Cada **projeto**."})
      assert render(view) =~ ~s(value="Exportações")

      assert_received {:asked, %{prompt: prompt}}
      assert prompt =~ "TITLE: Exports"
      assert prompt =~ "Every **project**."
    end

    test "the Assist menu changes a passage, and a rejection stops it", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin/news/new")
      assert html =~ "Fix spelling"

      FakeAI.answer(["Shorter."])

      render_hook(view, "kotoba:assist", %{
        "v" => 1,
        "id" => "tayori-body-en",
        "ref" => "k1",
        "action" => "shorter",
        "text" => "A much longer passage."
      })

      assert_push_event(view, "kotoba:stream", %{
        id: "tayori-body-en",
        ref: "k1",
        op: "start",
        at: "selection",
        label: "Shorter"
      })

      assert_push_event(view, "kotoba:stream", %{ref: "k1", op: "chunk", text: "Shorter."})
      assert_received {:asked, %{prompt: prompt}}
      assert prompt =~ "A much longer passage."

      render_hook(view, "kotoba:suggestion", %{
        "v" => 1,
        "id" => "tayori-body-en",
        "ref" => "k1",
        "action" => "reject"
      })

      assert render(view)
    end

    test "an error of the model cancels the suggestion and says so", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/news/new")
      view |> element("button", "Write with AI") |> render_click()
      FakeAI.answer({:error, :unauthorized})
      view |> form("#ai-draft", notes: "x") |> render_submit()

      assert_push_event(view, "kotoba:stream", %{op: "cancel"})
      assert render(view) =~ "The model did not answer."
    end

    test "a read-only admin has no AI", %{conn: conn} do
      {:ok, _view, html} = conn |> as_admin("viewer") |> live("/admin/news/new")
      refute html =~ "Write with AI"
    end
  end
end
