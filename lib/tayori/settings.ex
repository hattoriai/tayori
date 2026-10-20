defmodule Tayori.Settings do
  @moduledoc false
  # The settings the admin keeps in the app's database (tayori_settings):
  # a value as a map, and a secret, encrypted by the app's Cloak vault
  # (the :vault of Tayori's config), else with a key derived from its
  # :secret_key_base. The secret is never shown again: the admin can
  # replace it or remove it.

  alias Plug.Crypto.{KeyGenerator, MessageEncryptor}
  alias Tayori.Config

  @salt "tayori settings secret"
  @sign_salt "tayori settings secret signature"

  defmodule Setting do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:key, :string, autogenerate: false}
    schema "tayori_settings" do
      field :value, :map, default: %{}
      field :secret, :binary
      timestamps(type: :utc_datetime_usec)
    end
  end

  @doc "The value of a setting, a map (empty when it was never set)."
  def get(key) when is_binary(key) do
    case fetch(key) do
      %Setting{value: value} when is_map(value) -> value
      _ -> %{}
    end
  end

  @doc "Whether a setting has a secret."
  def secret?(key) when is_binary(key) do
    match?(%Setting{secret: secret} when is_binary(secret), fetch(key))
  end

  @doc "The secret of a setting, decrypted, or nil."
  def secret(key) when is_binary(key) do
    with %Setting{secret: secret} when is_binary(secret) <- fetch(key),
         {:ok, plain} <- decrypt(Config.get(), secret) do
      plain
    else
      _ -> nil
    end
  end

  @doc """
  Sets the value of a setting, and its secret: a string to encrypt,
  `:keep` to keep the one it has, or nil to remove it.
  """
  def put(key, value, secret \\ :keep) when is_binary(key) and is_map(value) do
    config = Config.get()
    setting = fetch(key) || %Setting{key: key}

    changes =
      case secret do
        :keep -> %{value: value}
        nil -> %{value: value, secret: nil}
        plain when is_binary(plain) -> %{value: value, secret: encrypt!(config, plain)}
      end

    setting
    |> Ecto.Changeset.change(changes)
    |> config.repo.insert_or_update!(prefix: config.prefix)

    :ok
  end

  defp fetch(key) do
    config = Config.get()
    config.repo.get(Setting, key, prefix: config.prefix)
  end

  @doc "Whether secrets can be kept: the config has a :vault or a :secret_key_base."
  def secrets? do
    config = Config.get()
    config.vault != nil or config.secret_key_base != nil
  end

  # The app's Cloak vault: its own keys, ciphers and rotation. Tayori
  # calls the functions every Cloak.Vault has, so it does not depend on
  # Cloak.
  defp encrypt!(%Config{vault: vault}, plain) when vault != nil do
    case vault.encrypt(plain) do
      {:ok, encrypted} ->
        encrypted

      {:error, error} ->
        raise ArgumentError, "the vault did not encrypt the secret: #{inspect(error)}"
    end
  end

  defp encrypt!(%Config{secret_key_base: nil}, _plain) do
    raise ArgumentError, "Tayori keeps no secret without the :vault or :secret_key_base option"
  end

  defp encrypt!(config, plain) do
    {secret, sign} = keys(config)
    MessageEncryptor.encrypt(plain, secret, sign)
  end

  defp decrypt(%Config{vault: vault}, encrypted) when vault != nil do
    case vault.decrypt(encrypted) do
      {:ok, plain} -> {:ok, plain}
      _error -> :error
    end
  rescue
    _ -> :error
  end

  defp decrypt(%Config{secret_key_base: nil}, _encrypted), do: :error

  defp decrypt(config, encrypted) do
    {secret, sign} = keys(config)
    MessageEncryptor.decrypt(encrypted, secret, sign)
  end

  defp keys(config) do
    {KeyGenerator.generate(config.secret_key_base, @salt, length: 32, cache: Plug.Crypto.Keys),
     KeyGenerator.generate(config.secret_key_base, @sign_salt,
       length: 32,
       cache: Plug.Crypto.Keys
     )}
  end
end
