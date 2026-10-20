defmodule Tayori.Subscribers do
  @moduledoc """
  Readers who get the news by email, from the public page: the
  `:subscriptions` feature.

  Every address is confirmed first: `subscribe/2` sends a link, and
  `confirm/1` takes its token. Each email has a link to unsubscribe
  (`unsubscribe/1`), which deletes the address. An entry is sent once,
  when it is published, if the admin chose to email it and it is for
  everyone (`Tayori.Entry`'s `:email`): a subscriber is an address, not a
  reader of the app, so an entry for some readers is never emailed.

  With the `:emails` config, the entries to email wait, and one email of
  them goes out on a schedule: `emails: [every: {:weekly, :monday}]`, or
  `:monthly`, or `{:days, n}`, at the `:at` time of day (UTC). It lists
  their titles and summaries with links to the public page; a period of
  one entry sends that entry, as it would alone. A period with none sends
  nothing. Each entry is sent once, in the first email after it is
  published (`emailed_at`).

  The emails go through the app's own Swoosh mailer (`:mailer`,
  `:email_from` and `:page_url` of `Tayori.Config`).
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Tayori.{Config, Digest, Entry}

  require Logger

  @setting "email_digest"

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          locale: String.t() | nil,
          token: String.t() | nil,
          confirmed_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tayori_subscribers" do
    field :email, :string
    field :locale, :string
    field :token, :string, redact: true
    field :confirmed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Subscribes an address, in a language: sends it a link to confirm. An
  address already confirmed gets nothing, and an address waiting for its
  confirmation gets the link again. The answer is the same in every case,
  so that the page tells no one who subscribed.
  """
  @spec subscribe(String.t(), String.t() | nil) :: :ok | {:error, Ecto.Changeset.t()}
  def subscribe(email, locale \\ nil) when is_binary(email) do
    config = Config.get()
    email = email |> String.trim() |> String.downcase()

    changeset =
      %__MODULE__{}
      |> change(email: email, locale: locale, token: token())
      |> validate_required([:email])
      |> validate_length(:email, max: 320)
      |> validate_format(:email, ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/, message: "is not an address")

    if changeset.valid? do
      # Two sign-ups of an address at once make one subscriber.
      config.repo.insert!(changeset,
        on_conflict: :nothing,
        conflict_target: :email,
        prefix: config.prefix
      )

      subscriber = config.repo.get_by!(__MODULE__, [email: email], prefix: config.prefix)

      if subscriber.confirmed_at == nil, do: send_confirmation(config, subscriber)

      :ok
    else
      {:error, changeset}
    end
  end

  # The reader asked for it a moment ago: sent now, in the request.
  defp send_confirmation(config, subscriber) do
    case config.mailer.deliver(Tayori.Mail.confirm(config, subscriber)) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Tayori could not email #{subscriber.id}: #{inspect(reason)}")
    end
  end

  @doc "Confirms the address of a token. Returns the subscriber, or `:error`."
  @spec confirm(String.t()) :: {:ok, t()} | :error
  def confirm(token) when is_binary(token) do
    config = Config.get()

    case config.repo.get_by(__MODULE__, [token: token], prefix: config.prefix) do
      nil ->
        :error

      %{confirmed_at: nil} = subscriber ->
        subscriber
        |> change(confirmed_at: DateTime.utc_now())
        |> config.repo.update(prefix: config.prefix)
        |> case do
          {:ok, subscriber} -> {:ok, subscriber}
          {:error, _} -> :error
        end

      subscriber ->
        {:ok, subscriber}
    end
  end

  @doc "Deletes the subscriber of a token. `:ok` whether or not there was one."
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(token) when is_binary(token) do
    config = Config.get()

    from(s in __MODULE__, where: s.token == ^token)
    |> config.repo.delete_all(prefix: config.prefix)

    :ok
  end

  @doc "The confirmed subscribers and those waiting, for the admin."
  @spec counts() :: %{confirmed: non_neg_integer(), waiting: non_neg_integer()}
  def counts do
    config = Config.get()

    from(s in __MODULE__,
      select: {count(s.confirmed_at), count(s.id)}
    )
    |> config.repo.one(prefix: config.prefix)
    |> then(fn {confirmed, all} -> %{confirmed: confirmed, waiting: all - confirmed} end)
  end

  @doc false
  # Claims an entry's email, once (its emailed_at), and returns the
  # confirmed subscribers to send it to, from the scheduler's
  # announcement. Two nodes never claim it both. An entry not to email,
  # or claimed already, has none.
  @spec claim_entry(Config.t(), Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def claim_entry(%Config{} = config, entry_id) do
    entry = Tayori.Entries.get(entry_id)

    if (entry && entry.email) and entry.segments == [] and each?(config) and
         Config.feature?(config, :subscriptions) and claim(config, entry_id) do
      confirmed(config)
    else
      []
    end
  end

  # An email for each entry, or one for the entries of a period.
  defp each?(%Config{emails: %{every: every}}), do: every == :each
  defp each?(_config), do: true

  defp confirmed(config) do
    from(s in __MODULE__,
      where: not is_nil(s.confirmed_at),
      order_by: s.inserted_at,
      select: s.id
    )
    |> config.repo.all(prefix: config.prefix)
  end

  defp claim(config, entry_id) do
    {count, _} =
      config.repo.update_all(
        from(e in Entry, where: e.id == ^entry_id and is_nil(e.emailed_at)),
        [set: [emailed_at: DateTime.utc_now()]],
        prefix: config.prefix
      )

    count == 1
  end

  @doc false
  # From the scheduler: sends the email of a period when its time has
  # come (the :emails config). The run is recorded first, in the
  # "email_digest" setting, so that the next look does not send it again.
  # The email takes the entries not emailed yet that were published since
  # the schedule began: those before were the time of an email each.
  @spec tick(Config.t(), DateTime.t()) :: :ok
  def tick(%Config{} = config, now) do
    if Config.feature?(config, :subscriptions) and not each?(config) do
      Digest.begin(@setting, now)
      last = Digest.last_run(@setting, now)

      if DateTime.compare(Digest.next_run(config.emails, last, now), now) != :gt do
        Digest.record(@setting, now)
        Tayori.Jobs.email_digest(config, Digest.began(@setting) || last)
      end
    end

    :ok
  end

  @doc false
  # The time of the next email of a period, or nil when each entry is
  # sent alone.
  @spec next_email_at(Config.t(), DateTime.t()) :: DateTime.t() | nil
  def next_email_at(%Config{} = config, now \\ DateTime.utc_now()) do
    if each?(config),
      do: nil,
      else: Digest.next_run(config.emails, Digest.last_run(@setting, now), now)
  end

  @doc false
  # Claims the entries of a period's email (the :emails config): those
  # published since a time and announced, to email, for everyone, not
  # emailed yet, each once. Returns their ids, the newest first, and the
  # confirmed subscribers to send them to; none when there is no entry.
  @spec claim_digest(Config.t(), DateTime.t()) :: {[Ecto.UUID.t()], [Ecto.UUID.t()]}
  def claim_digest(%Config{} = config, since) do
    if Config.feature?(config, :subscriptions) do
      ids =
        from(e in Entry,
          where:
            e.email == true and is_nil(e.emailed_at) and not is_nil(e.announced_at) and
              e.published_at > ^since,
          order_by: [desc: e.published_at],
          select: {e.id, e.segments}
        )
        |> config.repo.all(prefix: config.prefix)
        |> Enum.filter(fn {_id, segments} -> segments == [] end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.filter(&claim(config, &1))

      if ids == [], do: {[], []}, else: {ids, confirmed(config)}
    else
      {[], []}
    end
  end

  @doc false
  # Emails the entries of a period to one subscriber: an entry alone as
  # its own email, several as a list. One who unsubscribed since, or
  # entries deleted since, are nothing to send.
  @spec email_digest(Config.t(), [Ecto.UUID.t()], Ecto.UUID.t()) :: :ok | {:error, term()}
  def email_digest(%Config{} = config, entry_ids, subscriber_id) do
    with %__MODULE__{confirmed_at: %DateTime{}} = subscriber <-
           config.repo.get(__MODULE__, subscriber_id, prefix: config.prefix),
         [_ | _] = entries <- published(entry_ids) do
      email =
        case entries do
          [entry] -> Tayori.Mail.entry(config, entry, subscriber)
          entries -> Tayori.Mail.digest(config, entries, subscriber)
        end

      case config.mailer.deliver(email) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _gone -> :ok
    end
  end

  @doc false
  # Emails an entry to one subscriber. One who unsubscribed since, or an
  # entry deleted since, is nothing to send.
  @spec email(Config.t(), Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def email(%Config{} = config, entry_id, subscriber_id) do
    with %__MODULE__{confirmed_at: %DateTime{}} = subscriber <-
           config.repo.get(__MODULE__, subscriber_id, prefix: config.prefix),
         %Entry{} = entry <- Tayori.Entries.get(entry_id) do
      case config.mailer.deliver(Tayori.Mail.entry(config, entry, subscriber)) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _gone -> :ok
    end
  end

  # The entries still published, in the order of their ids.
  defp published(entry_ids) do
    entry_ids
    |> Enum.map(&Tayori.Entries.get/1)
    |> Enum.filter(&(&1 && Entry.status(&1) == :published))
  end

  defp token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
