defmodule Tayori.Notifier do
  @moduledoc """
  What the app does when an entry is published, beyond what Tayori sends
  itself (the emails of the `:subscriptions` feature, the webhooks of the
  `:webhooks` feature): a push, an email to the app's own users, a post
  elsewhere. The app knows its readers, its mailer and its voice.

      defmodule MyApp.NewsNotifier do
        @behaviour Tayori.Notifier

        @impl true
        def published(entry) do
          MyApp.Push.news(entry)
        end
      end

      {Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, notifier: MyApp.NewsNotifier}

  `c:published/1` is called once for each publication of an entry, by
  one node of the cluster, when the entry is published or, for a
  scheduled entry, when its time comes. An entry unpublished and published
  again is announced again.

  With the `:oban` option it runs in a job of `Tayori.Worker`, retried
  when it raises; without, in a task, where a crash is logged (see
  `Tayori.Jobs`).

  The entry has its translations, so the app can send each reader the
  language they read (`Tayori.Entry.translation/3`), and its segments, so
  it can send it to the readers it is for.
  """

  @callback published(Tayori.Entry.t()) :: any()
end
