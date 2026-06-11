defmodule Soundboard.AudioPlayer.CommercialScheduler do
  @moduledoc """
  GenServer that tracks voice channel inactivity and plays a random commercial
  clip when the configured inactivity threshold is exceeded.

  The timer resets whenever a user-initiated sound plays. Commercials themselves
  do not reset the timer so subsequent commercials can fire at the interval rate
  while the channel stays idle.
  """

  use GenServer

  require Logger

  alias Soundboard.{AudioPlayer, Commercials}
  alias Soundboard.Discord.{BotIdentity, GuildCache}

  @actor "BeeBot Commercial"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Resets the inactivity timer. Call this whenever a user plays a sound.
  """
  def reset_timer do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.cast(__MODULE__, :reset_timer)
    end
  end

  @doc """
  Reloads settings and restarts the timer. Call this after settings are saved.
  """
  def reload do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.cast(__MODULE__, :reload)
    end
  end

  @impl true
  def init(:ok) do
    {:ok, schedule_inactivity(%{timer_ref: nil})}
  end

  @impl true
  def handle_cast(:reset_timer, state) do
    {:noreply, state |> cancel_timer() |> schedule_inactivity()}
  end

  @impl true
  def handle_cast(:reload, state) do
    {:noreply, state |> cancel_timer() |> schedule_inactivity()}
  end

  @impl true
  def handle_info(:play_commercial, state) do
    play_if_ready()
    {:noreply, state |> Map.put(:timer_ref, nil) |> schedule_interval()}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp schedule_inactivity(state) do
    settings = Commercials.get_settings()

    if settings.enabled and settings.inactivity_seconds > 0 do
      ref = Process.send_after(self(), :play_commercial, settings.inactivity_seconds * 1_000)
      %{state | timer_ref: ref}
    else
      state
    end
  end

  defp schedule_interval(state) do
    settings = Commercials.get_settings()

    if settings.enabled and settings.interval_seconds > 0 do
      ref = Process.send_after(self(), :play_commercial, settings.interval_seconds * 1_000)
      %{state | timer_ref: ref}
    else
      state
    end
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  defp play_if_ready do
    with {:ok, {guild_id, channel_id}} <- AudioPlayer.current_voice_channel(),
         true <- humans_in_channel?(guild_id, channel_id),
         [_ | _] = clips <- Commercials.list_clips() do
      clip = Enum.random(clips)
      file_path = Commercials.clip_file_path(clip.filename)
      AudioPlayer.play_direct(clip.name, file_path, @actor)
    else
      reason ->
        Logger.debug("Commercial skipped: #{inspect(reason)}")
        :skip
    end
  end

  defp humans_in_channel?(guild_id, channel_id) do
    bot_id =
      case BotIdentity.fetch() do
        {:ok, %{id: id}} -> to_string(id)
        _ -> nil
      end

    case GuildCache.get(guild_id) do
      {:ok, guild} ->
        Enum.any?(
          guild.voice_states,
          &(&1.channel_id == to_string(channel_id) and &1.user_id != bot_id)
        )

      _ ->
        false
    end
  end
end
