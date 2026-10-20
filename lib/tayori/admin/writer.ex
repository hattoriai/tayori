defmodule Tayori.Admin.Writer do
  @moduledoc false
  # The AI of the editor: each request streams in a task, which sends its
  # text to the LiveView in batches; the LiveView streams it into the
  # language's editor as a Kotoba suggestion. A draft and a translation
  # begin with their title and summary (Tayori.AI.parse_header/1), which go
  # into the form, before the body streams into the editor.

  import Phoenix.Component, only: [assign: 3, update: 3]

  alias Tayori.AI

  # The time a task gathers text before it sends it, so that the editor
  # renders a few times a second, not once a token.
  @batch_ms 60

  @doc "Starts a request for an editor, with a Kotoba ref; returns the socket."
  def start(socket, ref, editor, locale, kind, task, opts \\ []) do
    live = self()

    {:ok, pid} =
      Task.Supervisor.start_child(Tayori.TaskSupervisor, fn -> run(live, ref, task) end)

    socket =
      Kotoba.Live.stream_start(socket, editor, ref,
        at: Keyword.get(opts, :at, :end),
        format: :markdown,
        label: Keyword.get(opts, :label, "AI")
      )

    update(socket, :writers, fn writers ->
      Map.put(writers, ref, %{
        pid: pid,
        editor: editor,
        locale: locale,
        kind: kind,
        header: if(kind in [:draft, :translate], do: :reading, else: :none),
        buffer: ""
      })
    end)
  end

  @doc "Stops a request, when the admin stops or rejects it."
  def stop(socket, ref) do
    case Map.pop(socket.assigns.writers, ref) do
      {nil, _writers} ->
        socket

      {writer, writers} ->
        Task.Supervisor.terminate_child(Tayori.TaskSupervisor, writer.pid)
        assign(socket, :writers, writers)
    end
  end

  @doc """
  Handles a message of a task. Returns `{socket, fields}`: the title and
  summary of a draft or a translation, once read, for the form.
  """
  def handle(socket, ref, message) do
    case Map.fetch(socket.assigns.writers, ref) do
      {:ok, writer} -> handle(socket, ref, writer, message)
      :error -> {socket, nil}
    end
  end

  defp handle(socket, ref, %{header: :reading} = writer, {:chunk, text}) do
    buffer = writer.buffer <> text

    case AI.parse_header(buffer) do
      {:ok, fields, rest} ->
        socket = put_writer(socket, ref, %{writer | header: :done, buffer: ""})
        {chunk(socket, writer.editor, ref, rest), {writer.locale, fields}}

      :more ->
        {put_writer(socket, ref, %{writer | buffer: buffer}), nil}
    end
  end

  defp handle(socket, ref, writer, {:chunk, text}) do
    {chunk(socket, writer.editor, ref, text), nil}
  end

  defp handle(socket, ref, writer, :done) do
    # A head that never ended: the model wrote the body alone.
    socket =
      if writer.buffer != "", do: chunk(socket, writer.editor, ref, writer.buffer), else: socket

    socket = Kotoba.Live.stream_end(socket, writer.editor, ref)
    {update(socket, :writers, &Map.delete(&1, ref)), nil}
  end

  defp handle(socket, ref, writer, {:error, _reason}) do
    socket = Kotoba.Live.stream_cancel(socket, writer.editor, ref)
    socket = update(socket, :writers, &Map.delete(&1, ref))

    {Phoenix.LiveView.put_flash(socket, :error, "The model did not answer. Check the settings."),
     nil}
  end

  defp chunk(socket, _editor, _ref, ""), do: socket
  defp chunk(socket, editor, ref, text), do: Kotoba.Live.stream_chunk(socket, editor, ref, text)

  defp put_writer(socket, ref, writer), do: update(socket, :writers, &Map.put(&1, ref, writer))

  # In the task: the text of the model, in batches, then :done.
  defp run(live, ref, task) do
    case AI.stream(task) do
      {:ok, stream} ->
        {pending, _at} = Enum.reduce(stream, {"", now()}, &batch(live, ref, &1, &2))
        if pending != "", do: send(live, {:tayori_ai, ref, {:chunk, pending}})
        send(live, {:tayori_ai, ref, :done})

      {:error, reason} ->
        send(live, {:tayori_ai, ref, {:error, reason}})
    end
  rescue
    error -> send(live, {:tayori_ai, ref, {:error, Exception.message(error)}})
  end

  defp batch(live, ref, text, {pending, at}) do
    pending = pending <> text

    if now() - at >= @batch_ms do
      send(live, {:tayori_ai, ref, {:chunk, pending}})
      {"", now()}
    else
      {pending, at}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
