defmodule SoundboardWeb.Live.Support.SoundPlayback do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3]

  alias Soundboard.Accounts.Permissions
  alias Soundboard.Accounts.User
  alias Soundboard.ClipCooldown
  alias Soundboard.PlaybackCooldown
  alias Soundboard.PubSubTopics

  def play(socket, sound_name) do
    if local_fake_playback_enabled?() do
      case ClipCooldown.check(sound_name) do
        :ok ->
          username =
            case socket.assigns[:current_user] do
              %User{username: username} when is_binary(username) and username != "" ->
                username

              _ ->
                "Local Tester"
            end

          {:noreply, play_locally_for_testing(socket, sound_name, username)}

        {:error, details} ->
          {:noreply, put_flash(socket, :error, ClipCooldown.message(details))}
      end
    else
      case socket.assigns[:current_user] do
        %User{id: user_id, username: username} = user ->
          if Permissions.can_play_clips?(socket.assigns[:current_user]) do
            case PlaybackCooldown.check(user) do
              :ok ->
                case ClipCooldown.check(sound_name) do
                  :ok ->
                    actor = %{display_name: username, user_id: user_id}
                    Soundboard.AudioPlayer.play_sound(sound_name, actor)
                    {:noreply, socket}

                  {:error, details} ->
                    {:noreply, put_flash(socket, :error, ClipCooldown.message(details))}
                end

              {:error, details} ->
                {:noreply, put_flash(socket, :error, PlaybackCooldown.message(details))}
            end
          else
            {:noreply,
             put_flash(socket, :error, "Your Discord role does not allow playing clips")}
          end

        _ ->
          {:noreply, put_flash(socket, :error, "You must be logged in to play sounds")}
      end
    end
  end

  defp local_fake_playback_enabled? do
    Application.get_env(:soundboard, :enable_local_fake_playback, false) or
      Application.get_env(:soundboard, :env) == :dev
  end

  defp play_locally_for_testing(socket, sound_name, username) do
    PubSubTopics.broadcast_sound_played(sound_name, username)
    push_event(socket, "play-local-sound", %{filename: sound_name})
  end

  def current_username(socket) do
    case socket.assigns[:current_user] do
      %User{username: username} -> {:ok, username}
      _ -> :error
    end
  end
end
