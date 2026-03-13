defmodule SoundboardWeb.Live.Support.SoundPlayback do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Soundboard.Accounts.Permissions
  alias Soundboard.Accounts.User

  def play(socket, sound_name) do
    case socket.assigns[:current_user] do
      %User{username: username} ->
        if Permissions.can_play_clips?(socket.assigns[:current_user]) do
          Soundboard.AudioPlayer.play_sound(sound_name, username)
          {:noreply, socket}
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
