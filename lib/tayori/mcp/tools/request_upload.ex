if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.RequestUpload do
    @moduledoc false
    use Sake.Tool,
      name: "request_upload",
      title: "Upload an image",
      description:
        "Get an address to upload one image to, such as a screenshot, for an entry's " <>
          "body: run the curl command it gives with the file's path (a PNG, JPEG, GIF or " <>
          "WebP, up to 25 MB), within ten minutes. curl answers JSON with the image's url " <>
          "and its Markdown, ![](url): put the alternative text, which becomes its caption, " <>
          "between the brackets, and the line alone in its paragraph of the body " <>
          "(create_entry, update_entry). One address takes one file.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: false]

    arg :filename, :string, max_length: 200, description: "The file's name (shot.png)"

    arg :content_type, :string,
      max_length: 100,
      description: "Its type (image/png); the file's bytes decide in the end"

    alias Tayori.Uploads

    @impl true
    def execute(args, _ctx) do
      case Uploads.request(args[:filename]) do
        {:ok, %{url: url, expires_at: expires_at}} ->
          file = args[:filename] || "shot.png"
          type = if args[:content_type], do: ";type=#{args[:content_type]}", else: ""

          {:ok,
           %{
             url: url,
             method: "POST",
             field: "file",
             curl: "curl -sS -F #{shell_quote("file=@" <> file <> type)} #{url}",
             expires_at: DateTime.to_iso8601(expires_at),
             max_bytes: Uploads.max_bytes()
           }}

        {:error, :no_upload_url} ->
          {:error,
           "This app takes no uploads: its :mcp config has no :upload_url. " <>
             "Send a small image (up to 1 MB) with upload_image instead."}
      end
    end

    defp shell_quote(text), do: "'" <> String.replace(text, "'", "'\\''") <> "'"
  end
end
