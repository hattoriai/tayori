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

      if subscriber.confirmed_at == nil,
        do: deliver(config, &Tayori.Mail.confirm(config, &1), [subscriber])

      :ok
    else
      {:error, changeset}
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
  # Emails an entry to the confirmed subscribers, once, from the
  # scheduler's announcement. The entry is claimed first (its emailed_at),
  # so that two nodes never send it twice.
  def send_entry(%Config{} = config, entry_id) do
    entry = Tayori.Entries.get!(entry_id)

    if entry.email and entry.segments == [] and Config.feature?(config, :subscriptions) and
         claim(config, entry_id) do
      from(s in __MODULE__, where: not is_nil(s.confirmed_at), order_by: s.inserted_at)
      |> config.repo.all(prefix: config.prefix)
      |> Enum.chunk_every(100)
      |> Enum.each(
        &deliver(config, fn subscriber -> Tayori.Mail.entry(config, entry, subscriber) end, &1)
      )
    end

    :ok
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

  defp deliver(config, build, subscribers) do
    for subscriber <- subscribers do
      case config.mailer.deliver(build.(subscriber)) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Tayori could not email #{subscriber.id}: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
