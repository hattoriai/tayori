if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.UploadImage do
    @moduledoc false
    use Sake.Tool,
      name: "upload_image",
      title: "Upload a small image",
      description:
        "Upload a small image (up to 1 MB) in the call, as base64, for a client that " <>
          "cannot run curl. For a screenshot, use request_upload: base64 is long to write. " <>
          "Returns the image's url and its Markdown, ![](url), as request_upload's upload does.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: false]

    arg :data, :string,
      required: true,
      max_length: 1_400_000,
      description: "The image's bytes in base64 (a data: URL too)"

    arg :filename, :string,
      required: true,
      max_length: 200,
      description: "The file's name (logo.png)"

    alias Tayori.Uploads

    @impl true
    def execute(%{data: data, filename: name}, _ctx) do
      case Uploads.store_base64(data, name) do
        {:ok, image} ->
          {:ok,
           %{
             url: image.url,
             markdown: "![](#{image.url})",
             name: image.name,
             content_type: image.content_type,
             bytes: image.bytes,
             width: image.width,
             height: image.height
           }}

        {:error, reason} ->
          {:error, message(reason)}
      end
    end

    defp message(:not_base64), do: "The data is not base64."
    defp message(:too_large), do: "The image is over 1 MB: use request_upload."
    defp message(:empty), do: "The data is empty."
    defp message(:not_an_image), do: "The data is not a PNG, JPEG, GIF or WebP image."
    defp message(_reason), do: "The image could not be stored."
  end
end
