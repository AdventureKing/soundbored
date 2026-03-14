defmodule Soundboard.AudioPlayer.PlaybackQueue do
  @moduledoc false

  require Logger

  alias Soundboard.AudioPlayer.{PlaybackEngine, SoundLibrary, State}
  alias Soundboard.ClipCooldown

  @type play_request :: %{
          guild_id: String.t(),
          channel_id: String.t(),
          sound_name: String.t(),
          path_or_url: String.t(),
          volume: number(),
          actor: term()
        }

  @spec build_request({String.t(), String.t()}, String.t(), term()) ::
          {:ok, play_request()} | {:error, String.t()}
  def build_request({guild_id, channel_id}, sound_name, actor) do
    case ClipCooldown.check(sound_name) do
      :ok ->
        case SoundLibrary.get_sound_path(sound_name) do
          {:ok, {path_or_url, volume}} ->
            {:ok,
             %{
               guild_id: guild_id,
               channel_id: channel_id,
               sound_name: sound_name,
               path_or_url: path_or_url,
               volume: volume,
               actor: actor
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, details} ->
        {:error, ClipCooldown.message(details)}
    end
  end

  @spec enqueue(State.t(), play_request()) :: State.t()
  def enqueue(%State{} = state, request) do
    case state.current_playback do
      nil ->
        start_playback(state, request)

      _ ->
        queue_request(state, request)
    end
  end

  @spec clear_all(State.t()) :: State.t()
  def clear_all(%State{} = state) do
    state
    |> clear_current_playback()
    |> Map.put(:pending_requests, [])
  end

  @spec handle_task_result(State.t(), term()) :: State.t()
  def handle_task_result(
        %State{current_playback: %{sound_name: sound_name} = current} = state,
        result
      ) do
    case result do
      :ok ->
        %{
          state
          | current_playback:
              current
              |> Map.put(:task_ref, nil)
              |> Map.put(:task_pid, nil)
        }

      :error ->
        Logger.error("Playback start failed for #{sound_name}")
        state |> clear_current_playback() |> maybe_start_next()
    end
  end

  def handle_task_result(%State{} = state, _result), do: state

  @spec handle_task_down(State.t(), term()) :: State.t()
  def handle_task_down(%State{} = state, reason) do
    Logger.error("Playback task crashed: #{inspect(reason)}")
    state |> clear_current_playback() |> maybe_start_next()
  end

  @spec handle_playback_finished(State.t(), String.t()) :: State.t()
  def handle_playback_finished(%State{} = state, guild_id) do
    if match?(%{guild_id: ^guild_id}, state.current_playback) do
      state
      |> clear_current_playback()
      |> maybe_start_next()
    else
      state
    end
  end

  defp start_playback(state, request) do
    task =
      Task.async(fn ->
        PlaybackEngine.play(
          request.guild_id,
          request.channel_id,
          request.sound_name,
          request.path_or_url,
          request.volume,
          request.actor
        )
      end)

    %{
      state
      | current_playback: request |> Map.put(:task_ref, task.ref) |> Map.put(:task_pid, task.pid)
    }
  end

  defp queue_request(%State{} = state, request) do
    Map.update(state, :pending_requests, [request], fn pending_requests ->
      case pending_requests do
        nil -> [request]
        _ -> pending_requests ++ [request]
      end
    end)
  end

  defp maybe_start_next(%State{} = state) do
    case pop_next_compatible_request(state.pending_requests || [], state.voice_channel) do
      {:ok, request, pending_requests} ->
        state
        |> Map.put(:pending_requests, pending_requests)
        |> start_playback(request)

      :none ->
        %{state | pending_requests: []}
    end
  end

  defp pop_next_compatible_request(nil, _voice_channel), do: :none
  defp pop_next_compatible_request([], _voice_channel), do: :none
  defp pop_next_compatible_request(_requests, nil), do: :none

  defp pop_next_compatible_request(
         [request | rest],
         {guild_id, channel_id} = voice_channel
       ) do
    if request.guild_id == guild_id and request.channel_id == channel_id do
      {:ok, request, rest}
    else
      pop_next_compatible_request(rest, voice_channel)
    end
  end

  defp clear_current_playback(%State{} = state) do
    cancel_playback_task(state.current_playback)
    %{state | current_playback: nil}
  end

  defp cancel_playback_task(nil), do: :ok

  defp cancel_playback_task(%{task_pid: pid, task_ref: ref}) when is_pid(pid) do
    if is_reference(ref), do: Process.demonitor(ref, [:flush])

    if Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    :ok
  end

  defp cancel_playback_task(_), do: :ok
end
