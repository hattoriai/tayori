defmodule Tayori.Notifier do
  @moduledoc """
  What the app does when an entry is published: an email to its readers,
  a message to a chat, a post elsewhere. Tayori sends nothing itself: the
  app knows its readers, its mailer and its voice.

      defmodule MyApp.NewsNotifier do
        @behaviour Tayori.Notifier

        @impl true
        def published(entry) do
          %{entry_id: entry.id}
          |> MyApp.Workers.NewsEmail.new()
          |> Oban.insert()

          :ok
        end
      end

      {Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, notifier: MyApp.NewsNotifier}

  `c:published/1` is called once for each publication of an entry, by
  one node of the cluster, when the entry is published or, for a
  scheduled entry, when its time comes. It runs in a task: a slow mailer
  holds nothing up, and a crash is logged. An entry unpublished and
  published again is announced again.

  The entry has its translations, so the app can send each reader the
  language they read (`Tayori.Entry.translation/3`), and its segments, so
  it can send it to the readers it is for.
  """

  @callback published(Tayori.Entry.t()) :: any()
end
