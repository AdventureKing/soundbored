defmodule SoundboardWeb.API.SoundController do
  use SoundboardWeb, :controller

  alias Soundboard.Accounts.Permissions
  alias Soundboard.ClipCooldown
  alias Soundboard.PlaybackCooldown
  alias Soundboard.{Repo, Sound, Sounds}

  def index(conn, _params) do
    current_user = conn.assigns[:current_user]

    sounds =
      Sound
      |> Sound.with_tags()
      |> Repo.all()
      |> Enum.map(&format_sound(&1, current_user))

    json(conn, %{data: sounds})
  end

  def create(conn, params) do
    with {:ok, user} <- require_upload_user(conn),
         :ok <- require_upload_permission(user),
         {:ok, sound} <- create_sound(user, params) do
      conn
      |> put_status(:created)
      |> json(%{data: format_sound(sound, user)})
    else
      {:error, :forbidden_auth_state} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Uploads require a user API token"})

      {:error, :insufficient_role} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Your Discord role does not allow uploading clips"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def play(conn, %{"id" => id}) do
    case Repo.get(Sound, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Sound not found"})

      sound ->
        case require_play_user(conn) do
          {:ok, user} ->
            case require_play_permission(user) do
              :ok ->
                case PlaybackCooldown.check(user) do
                  :ok ->
                    case ClipCooldown.check(sound) do
                      :ok ->
                        actor = %{display_name: user.username, user_id: user.id}

                        Soundboard.AudioPlayer.play_sound(sound.filename, actor)

                        conn
                        |> put_status(:accepted)
                        |> json(%{
                          data: %{
                            status: "accepted",
                            message: "Playback request accepted for #{sound.filename}",
                            requested_by: actor.display_name,
                            sound: %{id: sound.id, filename: sound.filename}
                          }
                        })

                      {:error, details} ->
                        conn
                        |> put_status(:too_many_requests)
                        |> json(%{
                          error: ClipCooldown.message(details),
                          retry_after_seconds: details.remaining_seconds
                        })
                    end

                  {:error, details} ->
                    conn
                    |> put_status(:too_many_requests)
                    |> json(%{
                      error: PlaybackCooldown.message(details),
                      retry_after_seconds: details.remaining_seconds
                    })
                end

              {:error, :insufficient_role} ->
                conn
                |> put_status(:forbidden)
                |> json(%{error: "Your Discord role does not allow playing clips"})
            end

          {:error, :forbidden_auth_state} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Playback requires a user API token"})
        end
    end
  end

  def stop(conn, _params) do
    Soundboard.AudioPlayer.stop_sound()

    conn
    |> put_status(:accepted)
    |> json(%{
      data: %{
        status: "accepted",
        message: "Stop request accepted"
      }
    })
  end

  defp create_sound(user, params) do
    user
    |> Sounds.new_create_request(params)
    |> Sounds.create_sound()
  end

  defp require_upload_user(conn) do
    case conn.assigns[:current_user] do
      %Soundboard.Accounts.User{} = user -> {:ok, user}
      _ -> {:error, :forbidden_auth_state}
    end
  end

  defp require_play_user(conn), do: require_upload_user(conn)

  defp require_upload_permission(user) do
    if Permissions.can_upload_clips?(user), do: :ok, else: {:error, :insufficient_role}
  end

  defp require_play_permission(user) do
    if Permissions.can_play_clips?(user), do: :ok, else: {:error, :insufficient_role}
  end

  defp format_sound(sound, _current_user) do
    %{
      id: sound.id,
      filename: sound.filename,
      source_type: sound.source_type,
      url: sound.url,
      volume: sound.volume,
      duration_ms: sound.duration_ms,
      internal_cooldown_seconds: sound.internal_cooldown_seconds,
      description: sound.description,
      tags: Enum.map(sound.tags || [], & &1.name),
      inserted_at: sound.inserted_at,
      updated_at: sound.updated_at
    }
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end
