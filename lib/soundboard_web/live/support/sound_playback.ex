defmodule SoundboardWeb.Live.Support.SoundPlayback do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Soundboard.Accounts.Permissions
  alias Soundboard.Accounts.User
  alias Soundboard.PlaybackCooldown

  def play(socket, sound_name) do
    case socket.assigns[:current_user] do
      %User{id: user_id, username: username} = user ->
        if Permissions.can_play_clips?(socket.assigns[:current_user]) do
          case PlaybackCooldown.check(user) do
            :ok ->
              actor = %{display_name: username, user_id: user_id}
              Soundboard.AudioPlayer.play_sound(sound_name, actor)
              {:noreply, socket}

            {:error, details} ->
              {:noreply, put_flash(socket, :error, PlaybackCooldown.message(details))}
          end
        else
          {:noreply, put_flash(socket, :error, "Your Discord role does not allow playing clips")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "You must be logged in to play sounds")}
    end
  end

  def current_username(socket) do
    case socket.assigns[:current_user] do
      %User{username: username} -> {:ok, username}
      _ -> :error
    end
  end
end
