defmodule Soundboard.Media.Duration do
  @moduledoc """
  Probes media duration in milliseconds using `ffprobe`.
  """

  require Logger

  @local_timeout_ms 5_000
  @url_timeout_ms 8_000

  @spec probe_local(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def probe_local(path) when is_binary(path) do
    probe(path, @local_timeout_ms)
  end

  @spec probe_url(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def probe_url(url) when is_binary(url) do
    probe(url, @url_timeout_ms)
  end

  @spec parse_duration_output(String.t()) :: {:ok, non_neg_integer()} | {:error, :invalid_duration}
  def parse_duration_output(output) when is_binary(output) do
    output
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.find_value(fn line ->
      case Float.parse(line) do
        {seconds, ""} when is_number(seconds) and seconds >= 0 ->
          {:ok, trunc(seconds * 1000)}

        _ ->
          nil
      end
    end)
    |> case do
      {:ok, duration_ms} -> {:ok, duration_ms}
      _ -> {:error, :invalid_duration}
    end
  end

  defp probe(input, timeout_ms) when is_binary(input) do
    with {:ok, ffprobe} <- ffprobe_path(),
         {:ok, output} <- run_ffprobe(ffprobe, input, timeout_ms),
         {:ok, duration_ms} <- parse_duration_output(output) do
      {:ok, duration_ms}
    else
      {:error, reason} ->
        Logger.debug("Duration probe failed for #{inspect(input)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ffprobe_path do
    case System.find_executable("ffprobe") do
      nil -> {:error, :ffprobe_not_found}
      path -> {:ok, path}
    end
  end

  defp run_ffprobe(ffprobe, input, timeout_ms) do
    args = [
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      input
    ]

    task =
      Task.async(fn ->
        System.cmd(ffprobe, args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, status}} ->
        {:error, {:ffprobe_failed, status, truncate_output(output)}}

      nil ->
        {:error, :timeout}

      {:exit, reason} ->
        {:error, {:ffprobe_crash, reason}}
    end
  end

  defp truncate_output(output) when is_binary(output) do
    output
    |> String.trim()
    |> String.slice(0, 200)
  end
end
