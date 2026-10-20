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

  The emails go through the app's own Swoosh mailer (`:mailer`,
  `:email_from` and `:page_url` of `Tayori.Config`).
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Tayori.{Config, Entry}

  require Logger

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
      subscriber =
        config.repo.get_by(__MODULE__, [email: email], prefix: config.prefix) ||
          config.repo.insert!(changeset, prefix: config.prefix)

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

    if (entry && entry.email) and entry.segments == [] and
         Config.feature?(config, :subscriptions) and claim(config, entry_id) do
      from(s in __MODULE__,
        where: not is_nil(s.confirmed_at),
        order_by: s.inserted_at,
        select: s.id
      )
      |> config.repo.all(prefix: config.prefix)
    else
      []
    end
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

  defp token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
