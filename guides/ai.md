# Writing with AI

The editor writes with AI, with your own key: a draft from what shipped, a
translation into another language, and a passage rewritten. The text
streams into the editor as a suggestion, which you accept or reject. AI
never publishes, and never changes an entry by itself.

## Set it up

Your app needs [ReqLLM](https://hex.pm/packages/req_llm), which speaks to
Anthropic, OpenAI, Google and many others:

```elixir
{:req_llm, "~> 1.6"}
```

and Tayori needs your app's `secret_key_base`, to keep the key encrypted:

```elixir
{Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, secret_key_base: secret_key_base}
```

Then, in the admin's Settings:

* **Model** - the provider and the model, as ReqLLM names them:
  `anthropic:claude-sonnet-5-5`, or `openai:<model>`, `google:<model>`.
* **API key** - your key with that provider. It is encrypted with a key
  derived from your `secret_key_base` (AES-GCM, `Plug.Crypto`), kept in
  `tayori_settings`, and never shown again: you can replace it or remove
  it. A new `secret_key_base` makes it unreadable; give it again.
* **About your product** - what it is, who uses it, and how it speaks.
  Every request carries it.

"Check the connection" asks the model a few words.

Only an admin with `:all` access writes with AI or changes the settings.

## In the editor

**Write with AI** opens the panel above the editor.

* **Draft** - paste what shipped: a list of changes, commit messages, the
  titles of pull requests. The model writes an entry in the language of
  the tab: its title and summary go into the form (when they are empty),
  and its body streams into the editor.
* **Translate** - in a language other than the first, the model writes the
  first language's version in this one: its title, summary and body.

Select a passage, and the editor's **Assist** menu has:

* **Rewrite** - clearer and more direct;
* **Shorter** - what matters to the reader;
* **Warmer** - more personal, without hype;
* **Fix spelling** - the spelling and the grammar only.

Each suggestion shows under the editor as it streams, with Accept and
Reject; accepting puts it in the body as one step of undo.

## The prompts

The model is told to write for the people who use the product, not its
developers; to say what changed and what it lets them do, in plain words;
never to invent a feature, a number or a detail; and to write in the
language of the tab. "About your product" follows.

## Privacy

What you paste, and the entry when you translate it, go to the provider of
your model, with your key, from your server. Tayori sends nothing
anywhere else.
