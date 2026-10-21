defmodule Tayori.AI do
  @moduledoc """
  Writing the news with AI, with the key of the app: a draft from what
  shipped, a translation into another language, and changes to a
  passage (rewrite, shorter, warmer, fix the spelling).

  The admin chooses the model and gives the key in its Settings: any model
  that [ReqLLM](https://hex.pm/packages/req_llm) knows, such as
  `anthropic:claude-sonnet-5-5`, or a model of OpenAI or Google. The key is encrypted
  by the app's Cloak vault (`:vault`), else with the `:secret_key_base` of
  Tayori's config, kept in the app's database, and never shown again. The app needs the dependency:

      {:req_llm, "~> 1.6"}

  The text streams into the editor as a suggestion, which the admin
  accepts or rejects (Kotoba's suggestions): AI never publishes, and
  never changes an entry by itself.

  The admin can also say what the product is and how it speaks
  ("About your product"), which every request carries.

  Outside the editor, `complete/2` waits for the whole text: a digest
  writes its entry from the inbox's changes with it (`Tayori.Digest`),
  a draft unless the `:digest` config says to publish it.
  """

  alias Tayori.{Categories, Category, Config, Locales, Settings}

  @setting "ai"

  @doc "The adapter that calls the model: `stream(model, key, system, prompt)`."
  @callback stream(
              model :: String.t(),
              key :: String.t(),
              system :: String.t(),
              prompt :: String.t()
            ) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @actions %{
    "rewrite" => "Rewrite it to be clearer and more direct, with the same meaning.",
    "shorter" => "Make it shorter: keep what matters to the reader, drop the rest.",
    "warmer" => "Make it warmer and more personal, without hype.",
    "fix" => "Fix the spelling and the grammar only; change nothing else."
  }

  @doc "The actions on a passage, `[{id, label}]`, for the editor's Assist menu."
  @spec actions() :: [{String.t(), String.t()}]
  def actions do
    [
      {"rewrite", "Rewrite"},
      {"shorter", "Shorter"},
      {"warmer", "Warmer"},
      {"fix", "Fix spelling"}
    ]
  end

  @doc "Whether the app can use AI: it has ReqLLM, and Tayori can keep a key."
  @spec available?() :: boolean()
  def available?, do: adapter_loaded?() and Settings.secrets?()

  @doc "Whether the admin has given a model and a key."
  @spec configured?() :: boolean()
  def configured? do
    available?() and settings().model not in [nil, ""] and Settings.secret?(@setting)
  end

  @doc """
  The settings, without the key: `%{model: ..., about: ..., key?: bool}`.
  """
  @spec settings() :: %{model: String.t() | nil, about: String.t() | nil, key?: boolean()}
  def settings do
    value = Settings.get(@setting)
    %{model: value["model"], about: value["about"], key?: Settings.secret?(@setting)}
  end

  @doc """
  Saves the model and what the product is; the key is a string to keep,
  `:keep`, or nil to remove it.
  """
  @spec save_settings(map(), String.t() | :keep | nil) :: :ok
  def save_settings(%{} = params, key \\ :keep) do
    value = %{
      "model" => params |> Map.get("model", "") |> String.trim(),
      "about" => params |> Map.get("about", "") |> String.trim() |> String.slice(0, 2000)
    }

    Settings.put(@setting, value, key)
  end

  @doc """
  Streams the text of a task, as a stream of strings:

    * `{:draft, notes, locale}` - an entry from notes of what shipped (a
      list of changes, commits, pull requests), with a title and a
      summary first (see `parse_header/1`);
    * `{:digest, changes, locale}` - an entry from changes of the inbox
      (`Tayori.Change`), in the same form;
    * `{:translate, %{title:, summary:, markdown:}, from, to}` - an entry
      in another language, in the same form;
    * `{:assist, action, text, locale}` - a passage changed by an action of
      `actions/0`.
  """
  @spec stream(tuple()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(task) do
    with true <- configured?() || {:error, :not_configured},
         {:ok, {system, prompt}} <- prompt(task) do
      adapter().stream(settings().model, Settings.secret(@setting), system, prompt)
    end
  end

  @doc """
  The whole text of a task (see `stream/1`), for a request that no one
  watches as it streams. Options: `:timeout`, in milliseconds (two
  minutes). Returns `{:ok, text}`, or `{:error, reason}`: `:timeout` when
  the model takes longer.
  """
  @spec complete(tuple(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def complete(task, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :timer.minutes(2))

    with {:ok, stream} <- stream(task) do
      reader = Task.Supervisor.async_nolink(Tayori.TaskSupervisor, fn -> read(stream) end)

      case Task.yield(reader, timeout) || Task.shutdown(reader, :brutal_kill) do
        {:ok, result} -> result
        {:exit, reason} -> {:error, reason}
        nil -> {:error, :timeout}
      end
    end
  end

  defp read(stream) do
    {:ok, Enum.join(stream)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  @doc """
  Checks the model and the key with a request of a few words. Returns
  `:ok` or `{:error, reason}`.
  """
  @spec check() :: :ok | {:error, term()}
  def check do
    with {:ok, stream} <- stream({:assist, "fix", "Hello.", "en"}) do
      _ = Enum.take(stream, 1)
      :ok
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @doc """
  Reads the head of a draft or a translation, `TITLE:` and `SUMMARY:`
  lines and a `---` line, from the text streamed so far.

  ## Examples

      iex> Tayori.AI.parse_header("TITLE: Exports\\nSUMMARY: In two clicks.\\n---\\nEvery project")
      {:ok, %{title: "Exports", summary: "In two clicks."}, "Every project"}

      iex> Tayori.AI.parse_header("TITLE: Exp")
      :more

  """
  @spec parse_header(String.t()) :: {:ok, map(), String.t()} | :more
  def parse_header(text) do
    case String.split(text, ~r/^---[ \t]*\r?\n/m, parts: 2) do
      [head, rest] ->
        fields =
          for line <- String.split(head, "\n"),
              [_, key, value] <- [Regex.run(~r/^\s*(TITLE|SUMMARY)\s*:\s*(.*)$/i, line)],
              into: %{},
              do: {key |> String.downcase() |> String.to_existing_atom(), String.trim(value)}

        {:ok, Map.merge(%{title: nil, summary: nil}, fields), rest}

      [_head] ->
        :more
    end
  end

  # The prompts.

  defp prompt({:draft, notes, locale}) do
    ok(
      system(locale),
      """
      Write an entry of the product's news from these notes of what shipped.

      Reply in this form, and nothing else:

      TITLE: a title of a few words, in sentence case
      SUMMARY: one or two sentences for the news panel and the emails
      ---
      the body, in Markdown: what changed and what it lets people do, in a
      few short paragraphs, with a list when there are several changes.

      The notes:

      #{notes}
      """
    )
  end

  defp prompt({:digest, changes, locale}) do
    ok(
      system(locale),
      """
      Write one entry of the product's news from these changes, which
      shipped since the last entry.

      Put together the changes that belong together, and lead with those
      marked as highlights. Say what people can do now, not how it was
      built: leave out the names in the code, the numbers of tickets and
      pull requests, and what no one who uses the product would notice.
      Say only what the changes say.

      Reply in this form, and nothing else:

      TITLE: a title of a few words, in sentence case, of what matters most
      SUMMARY: one or two sentences for the news panel and the emails
      ---
      the body, in Markdown: the highlights first, in a few short
      paragraphs, then the rest as a list, under a heading for each kind
      of change when there are several.

      The changes:

      #{changes(changes, locale)}
      """
    )
  end

  defp prompt({:translate, %{title: title, summary: summary, markdown: markdown}, from, to}) do
    ok(
      system(to),
      """
      Translate this entry of the product's news from #{language(from)} into
      #{language(to)}. Keep its meaning, its Markdown, its links and the names
      of the product's features; write it as a native speaker would.

      Reply in this form, and nothing else:

      TITLE: the title
      SUMMARY: the summary (empty if it has none)
      ---
      the body, in Markdown

      The entry:

      TITLE: #{title}
      SUMMARY: #{summary}
      ---
      #{markdown}
      """
    )
  end

  defp prompt({:assist, action, text, locale}) do
    case Map.fetch(@actions, action) do
      {:ok, instruction} ->
        ok(
          system(locale),
          """
          #{instruction} Reply with the passage alone, in Markdown, in the
          language it is written in.

          The passage:

          #{text}
          """
        )

      :error ->
        {:error, :unknown_action}
    end
  end

  defp prompt(_task), do: {:error, :unknown_task}

  defp ok(system, prompt), do: {:ok, {system, prompt}}

  # The changes of a digest as the model reads them: what they say, their
  # category and whether they lead; not their refs, links or authors.
  defp changes(changes, locale) do
    categories = Categories.by_key()
    locales = Config.get().locales

    Enum.map_join(changes, "\n", fn change ->
      marks =
        Enum.filter(
          [
            change.highlight && "highlight",
            category_name(categories[change.category], locale, locales)
          ],
          & &1
        )

      marks = if marks == [], do: "", else: " (" <> Enum.join(marks, "; ") <> ")"
      "- " <> change.title <> marks <> indented(change.body)
    end)
  end

  defp indented(body) when is_binary(body) and body != "",
    do: "\n" <> (body |> String.trim() |> String.replace(~r/^/m, "  "))

  defp indented(_body), do: ""

  defp category_name(%Category{} = category, locale, locales),
    do: Category.name(category, locale, locales)

  defp category_name(_none, _locale, _locales), do: nil

  defp system(locale) do
    about =
      case settings().about do
        blank when blank in [nil, ""] -> ""
        about -> "\n\nAbout the product, in its makers' words:\n\n" <> about
      end

    """
    You write the product news of an app: the entries of its changelog,
    which the people who use it read in the app, on its public page and in
    their email. Write for them, not for its developers: what changed, and
    what it lets them do. Plain words, short sentences, the active voice.
    No hype, no exclamation marks. Never invent a feature, a number or a
    detail that the text you are given does not have. Write in
    #{language(locale)}.#{about}
    """
  end

  defp language(locale) do
    # A language the app does not name is told by its tag.
    case Locales.name(locale) do
      ^locale -> "the language whose BCP 47 tag is #{locale}"
      name -> "#{name} (#{locale})"
    end
  end

  defp adapter, do: Application.get_env(:tayori, :ai_adapter, Tayori.AI.ReqLLM)

  defp adapter_loaded? do
    case adapter() do
      Tayori.AI.ReqLLM -> Code.ensure_loaded?(ReqLLM)
      other -> Code.ensure_loaded?(other)
    end
  end
end

defmodule Tayori.AI.ReqLLM do
  @moduledoc false
  # The model, through ReqLLM, with the key of the app.

  @behaviour Tayori.AI

  @compile {:no_warn_undefined, [ReqLLM, ReqLLM.Context, ReqLLM.StreamResponse]}

  @impl true
  def stream(model, key, system, prompt) do
    context = ReqLLM.Context.new([ReqLLM.Context.system(system), ReqLLM.Context.user(prompt)])

    case ReqLLM.stream_text(model, context, api_key: key) do
      {:ok, response} -> {:ok, ReqLLM.StreamResponse.tokens(response)}
      {:error, error} -> {:error, error}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end
end
