if Code.ensure_loaded?(Oban.Worker) do
  defmodule Tayori.Worker do
    @moduledoc """
    The Oban worker of Tayori: an email to a subscriber, a webhook, or the
    call to the app's notifier, when an entry is published. Tayori enqueues
    its jobs itself, with the `:oban` option of `Tayori.Config`; see
    `Tayori.Jobs`.
    """

    use Oban.Worker, queue: :default

    @impl Oban.Worker
    def perform(%Oban.Job{args: args}), do: Tayori.Jobs.perform(Tayori.Config.get(), args)
  end
end
