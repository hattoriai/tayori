defmodule Tayori.Uploads do
  @moduledoc false
  # The images an agent puts in an entry over MCP (`Tayori.MCP`): a
  # screenshot is too big to write in a tool's arguments, so the agent asks
  # for an upload (`request/1`), and sends the file to the uploads route of
  # `tayori_api` (`POST <api>/uploads/:token`, `Tayori.API`), with curl.
  #
  # A token is good for one file, for ten minutes. Only its hash is kept,
  # in tayori_settings (`"mcp_upload:<hash>"`), so the table never holds a
  # token that works. The file is stored as the admin's editor stores one
  # (`Kotoba.Attachments.store/2`, the `:storage` of the `:mcp` config),
  # and only when its bytes are an image: PNG, JPEG, GIF or WebP, of the
  # editor's size at most.
  #
  # Each stored image is remembered by its URL (`"mcp_file:<hash>"`), with
  # its size and type, so that `![caption](url)` in an entry's Markdown
  # becomes the attachment it is, a figure with its caption
  # (`content/1`), as a file dropped in the editor does. A URL Tayori did
  # not store stays a plain image: nothing is ever fetched from one.

  import Ecto.Query

  alias Kotoba.Nodes.Attachment
  alias Tayori.{Config, Translation}
  alias Tayori.Settings.Setting

  @upload "mcp_upload:"
  @file_key "mcp_file:"
  @ttl 600
  @images ~w(image/png image/jpeg image/gif image/webp)

  # As the admin's editor.
  @max_bytes 25_000_000
  @max_inline 1_000_000

  @doc "The most bytes of an uploaded file."
  def max_bytes, do: @max_bytes

  @doc "The most bytes of an image sent in a tool call."
  def max_inline, do: @max_inline

  @doc "How long a token is good for, in seconds."
  def ttl, do: @ttl

  @doc """
  A new token, for one file: `{:ok, %{url: ..., expires_at: ...}}`, or
  `{:error, :no_upload_url}` when the `:mcp` config has none.
  """
  def request(name \\ nil) do
    config = Config.get()

    case config.mcp do
      %{upload_url: url} when is_binary(url) ->
        prune(config)
        token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        expires_at = DateTime.add(DateTime.utc_now(), @ttl, :second)

        %Setting{key: @upload <> hash(token), value: %{"name" => name}}
        |> config.repo.insert!(prefix: config.prefix)

        {:ok, %{url: url <> "/" <> token, expires_at: expires_at}}

      _ ->
        {:error, :no_upload_url}
    end
  end

  # The tokens past their time.
  defp prune(config) do
    from(s in Setting,
      where: like(s.key, ^(@upload <> "%")) and s.inserted_at < ^cutoff()
    )
    |> config.repo.delete_all(prefix: config.prefix)
  end

  defp cutoff, do: DateTime.add(DateTime.utc_now(), -@ttl, :second)

  @doc """
  The name a token was asked with (or nil), while it is good:
  `{:ok, name}`, or `:error`.
  """
  def check(token) when is_binary(token) do
    config = Config.get()

    from(s in Setting,
      where: s.key == ^(@upload <> hash(token)) and s.inserted_at >= ^cutoff(),
      select: s.value
    )
    |> config.repo.one(prefix: config.prefix)
    |> case do
      %{} = value -> {:ok, value["name"]}
      nil -> :error
    end
  end

  @doc "Uses a token up: `:ok` once, `:error` after, or for a token past its time."
  def consume(token) when is_binary(token) do
    config = Config.get()

    from(s in Setting,
      where: s.key == ^(@upload <> hash(token)) and s.inserted_at >= ^cutoff()
    )
    |> config.repo.delete_all(prefix: config.prefix)
    |> case do
      {1, _} -> :ok
      _ -> :error
    end
  end

  @doc """
  Stores the image at `path`: `{:ok, attachment}`, or `{:error, reason}`
  (`:too_large`, `:not_an_image`, or the storage's).
  """
  def store(path, name, claim) do
    config = Config.get()

    with {:ok, %{bytes: bytes, content_type: type}} <- Kotoba.Attachments.describe(path, claim),
         :ok <- check_size(bytes, @max_bytes),
         :ok <- check_image(type),
         {:ok, %Attachment{} = image} <-
           Kotoba.Attachments.store(path, store_opts(config, name || "image", type)) do
      remember(config, image)
      {:ok, image}
    end
  end

  defp store_opts(config, name, type) do
    opts = [name: name, content_type: type]

    case config.mcp do
      %{storage: storage} when storage != nil -> [storage: storage] ++ opts
      _ -> opts
    end
  end

  @doc "Stores an image sent in a tool call, as base64."
  def store_base64(data, name) do
    with {:ok, binary} <- decode(data),
         :ok <- check_size(byte_size(binary), @max_inline) do
      path = Plug.Upload.random_file!("tayori-mcp")

      try do
        File.write!(path, binary)
        store(path, name, nil)
      after
        File.rm(path)
      end
    end
  end

  defp decode(data) do
    data = String.replace(data, ~r/\s+/, "")

    data =
      case String.split(data, ";base64,", parts: 2) do
        ["data:" <> _type, base64] -> base64
        _ -> data
      end

    case Base.decode64(data, padding: false) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :not_base64}
    end
  end

  @doc false
  def check_size(bytes, max) when bytes > max, do: {:error, :too_large}
  def check_size(0, _max), do: {:error, :empty}
  def check_size(_bytes, _max), do: :ok

  defp check_image(type) when type in @images, do: :ok
  defp check_image(_type), do: {:error, :not_an_image}

  defp remember(config, %Attachment{} = image) do
    value = %{
      "key" => image.key,
      "url" => image.url,
      "name" => image.name,
      "content_type" => image.content_type,
      "bytes" => image.bytes,
      "width" => image.width,
      "height" => image.height
    }

    %Setting{key: @file_key <> hash(image.url), value: value}
    |> config.repo.insert!(
      prefix: config.prefix,
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )
  end

  @doc "The image Tayori stored at a URL, or nil."
  def attachment(url) when is_binary(url) do
    config = Config.get()

    case config.repo.get(Setting, @file_key <> hash(url), prefix: config.prefix) do
      %Setting{value: %{"url" => ^url} = v} ->
        %Attachment{
          key: v["key"],
          url: v["url"],
          name: v["name"],
          content_type: v["content_type"],
          bytes: v["bytes"],
          width: v["width"],
          height: v["height"]
        }

      _ ->
        nil
    end
  end

  @image ~r/!\[([^\]\n]*)\]\(\s*<?([^)\s>]+)>?\s*\)/

  @doc """
  The body of an entry from Markdown: an image Tayori stored becomes its
  attachment, with the alternative text as its caption, when it stands
  in a paragraph of its own (alone, or with other such images, a
  gallery); any other image stays an image.
  """
  def content(markdown) when is_binary(markdown) do
    {blocks, attachments} =
      markdown
      |> String.split(~r/\n[ \t]*\n/)
      |> Enum.map_reduce(%{}, &block/2)

    Kotoba.Content.from_markdown(Enum.join(blocks, "\n\n"),
      features: Translation.features(),
      attachments: attachments
    )
  end

  defp block(block, attachments) do
    images = Regex.scan(@image, block)

    if images != [] and String.trim(Regex.replace(@image, block, "")) == "" do
      Enum.reduce(images, {block, attachments}, &image/2)
    else
      {block, attachments}
    end
  end

  defp image([image, alt, url], {block, attachments}) do
    case attachment(url) do
      %Attachment{} = node ->
        name = "upload#{map_size(attachments)}"

        {String.replace(block, image, "![#{alt}](attachment:#{name})", global: false),
         Map.put(attachments, name, node)}

      nil ->
        {block, attachments}
    end
  end

  defp hash(value),
    do: Base.url_encode64(:crypto.hash(:sha256, value), padding: false)
end
