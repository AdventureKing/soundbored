defmodule Soundboard.Sounds.Management do
  @moduledoc """
  Domain-level sound update/delete operations used by LiveViews.

  Sound metadata edits are collaborative for signed-in users. Deletion is
  allowed for the original uploader and settings admins. Per-user join/leave
  preferences are stored separately so editors keep their own settings without
  taking over sound ownership.
  """

  alias Soundboard.Accounts.{Permissions, User}
  alias Soundboard.{AudioPlayer, Repo, Sound, UploadsPath, Volume}
  require Logger

  def update_sound(%Sound{} = sound, user_id, params) do
    Repo.transaction(fn ->
      db_sound =
        Repo.get!(Sound, sound.id)
        |> Repo.preload(:user_sound_settings)

      old_path = UploadsPath.file_path(db_sound.filename)
      new_filename = params["filename"] <> Path.extname(db_sound.filename)
      new_path = UploadsPath.file_path(new_filename)
      can_manage_internal_cooldown = can_manage_internal_cooldown?(user_id)

      sound_params = %{
        filename: new_filename,
        source_type: params["source_type"] || db_sound.source_type,
        url: params["url"],
        user_id: db_sound.user_id || user_id,
        internal_cooldown_seconds:
          internal_cooldown_seconds_param(
            params,
            db_sound.internal_cooldown_seconds,
            can_manage_internal_cooldown
          ),
        volume:
          params["volume"]
          |> Volume.percent_to_decimal(Volume.decimal_to_percent(db_sound.volume))
      }

      updated_sound =
        case Sound.changeset(db_sound, sound_params) |> Repo.update() do
          {:ok, updated_sound} ->
            updated_sound = update_user_settings(db_sound, user_id, updated_sound, params)
            AudioPlayer.invalidate_cache(db_sound.filename)
            AudioPlayer.invalidate_cache(updated_sound.filename)
            updated_sound

          {:error, changeset} ->
            Repo.rollback(changeset)
        end

      case maybe_rename_local_file(db_sound, old_path, new_path) do
        :ok -> updated_sound
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  def delete_sound(%Sound{} = sound, actor) do
    db_sound = Repo.get!(Sound, sound.id)

    with true <- can_delete_sound?(db_sound, actor),
         {:ok, _deleted_sound} <- Repo.delete(db_sound) do
      AudioPlayer.invalidate_cache(db_sound.filename)
      maybe_remove_local_file(db_sound)
      :ok
    else
      false -> {:error, :forbidden}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp maybe_remove_local_file(%{source_type: "local", filename: filename}) do
    _ = File.rm(UploadsPath.file_path(filename))
    :ok
  end

  defp maybe_remove_local_file(_), do: :ok

  defp can_delete_sound?(%Sound{user_id: owner_id}, %{id: actor_id} = actor)
       when is_integer(actor_id) do
    actor_id == owner_id or Permissions.can_manage_settings?(actor)
  end

  defp can_delete_sound?(%Sound{user_id: owner_id}, actor_id) when is_integer(actor_id) do
    if actor_id == owner_id do
      true
    else
      Repo.get(Soundboard.Accounts.User, actor_id)
      |> Permissions.can_manage_settings?()
    end
  end

  defp can_delete_sound?(_, _), do: false

  defp maybe_rename_local_file(%{source_type: "local"} = sound, old_path, new_path) do
    cond do
      sound.filename == Path.basename(new_path) ->
        :ok

      old_path == new_path ->
        :ok

      not File.exists?(old_path) ->
        Logger.error("Source file not found: #{old_path}")
        {:error, "Source file not found"}

      true ->
        case File.rename(old_path, new_path) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("File rename failed: #{inspect(reason)}")
            {:error, "Failed to rename file: #{inspect(reason)}"}
        end
    end
  end

  defp maybe_rename_local_file(_, _, _), do: :ok

  defp update_user_settings(sound, user_id, updated_sound, params) do
    user_setting =
      Enum.find(sound.user_sound_settings, &(&1.user_id == user_id)) ||
        %Soundboard.UserSoundSetting{sound_id: sound.id, user_id: user_id}

    setting_params = %{
      user_id: user_id,
      sound_id: sound.id,
      is_join_sound: params["is_join_sound"] == "true",
      is_leave_sound: params["is_leave_sound"] == "true"
    }

    Soundboard.UserSoundSetting.clear_conflicting_settings(
      user_id,
      sound.id,
      setting_params.is_join_sound,
      setting_params.is_leave_sound
    )

    case user_setting
         |> Soundboard.UserSoundSetting.changeset(setting_params)
         |> Repo.insert_or_update() do
      {:ok, _setting} ->
        updated_sound

      {:error, changeset} ->
        Logger.error("Failed to update user settings: #{inspect(changeset)}")
        Repo.rollback(changeset)
    end
  end

  defp can_manage_internal_cooldown?(user_id) when is_integer(user_id) do
    Repo.get(User, user_id)
    |> Permissions.can_manage_settings?()
  end

  defp can_manage_internal_cooldown?(_), do: false

  defp internal_cooldown_seconds_param(params, current_value, true) do
    case Map.fetch(params, "internal_cooldown_seconds") do
      {:ok, value} -> value
      :error -> current_value
    end
  end

  defp internal_cooldown_seconds_param(_params, current_value, false), do: current_value
end
