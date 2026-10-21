if Code.ensure_loaded?(Oban.Worker) do
  defmodule Tayori.Worker do
    @moduledoc """
    The Oban worker of Tayori: an email to a subscriber, a webhook, or the
    call to the app's notifier, when an entry is published; a digest of the
    inbox, or the email of a period's entries, on schedule; and the
    campaigns' work, a person of a sequence at their next time, a
    broadcast at its time, and each letter. Tayori enqueues
    its jobs itself, with the `:oban` option of `Tayori.Config`; see
    `Tayori.Jobs`.
    """

    use Oban.Worker, queue: :default

    @impl Oban.Worker
    def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
      Tayori.Jobs.perform(Tayori.Config.get(), args, %{
        attempt: attempt,
        max_attempts: max_attempts
      })
    end
  end
end
