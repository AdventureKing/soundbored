defmodule Soundboard.Sounds.ManagementTest do
  use Soundboard.DataCase

  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Sound}
  alias Soundboard.Sounds.Management

  setup do
    original_admin_user_ids =
      Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

    on_exit(fn ->
      Application.put_env(:soundboard, :discord_settings_admin_user_ids, original_admin_user_ids)
    end)

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "mgmt_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    %{user: user}
  end

  test "delete_sound/2 removes local file and record", %{user: user} do
    filename = "delete_#{System.unique_integer([:positive])}.mp3"
    sound = insert_local_sound(user, filename)

    local_path = Path.join(uploads_dir(), filename)
    File.write!(local_path, "audio")
    on_exit(fn -> File.rm(local_path) end)
    assert File.exists?(local_path)

    with_mock Soundboard.AudioPlayer, invalidate_cache: fn ^filename -> :ok end do
      assert :ok = Management.delete_sound(sound, user.id)
      assert_called(Soundboard.AudioPlayer.invalidate_cache(filename))
    end

    refute File.exists?(local_path)
    assert Repo.get(Sound, sound.id) == nil
  end

  test "update_sound/3 renames local file", %{user: user} do
    filename = "old_#{System.unique_integer([:positive])}.mp3"
    sound = insert_local_sound(user, filename)

    old_path = Path.join(uploads_dir(), filename)
    File.write!(old_path, "audio")
    on_exit(fn -> File.rm(old_path) end)

    params = %{
      "filename" => "renamed_#{System.unique_integer([:positive])}",
      "source_type" => "local",
      "url" => nil,
      "volume" => "80"
    }

    new_filename = params["filename"] <> ".mp3"

    with_mock Soundboard.AudioPlayer,
      invalidate_cache: fn cache_key when cache_key in [filename, new_filename] -> :ok end do
      assert {:ok, updated_sound} = Management.update_sound(sound, user.id, params)

      assert_called(Soundboard.AudioPlayer.invalidate_cache(filename))
      assert_called(Soundboard.AudioPlayer.invalidate_cache(new_filename))

      new_path = Path.join(uploads_dir(), new_filename)
      on_exit(fn -> File.rm(new_path) end)

      assert updated_sound.filename == new_filename
      assert File.exists?(new_path)
      refute File.exists?(old_path)
    end
  end

  test "update_sound/3 keeps sound metadata collaborative while preserving uploader ownership", %{
    user: user
  } do
    filename = "shared_#{System.unique_integer([:positive])}.mp3"
    sound = insert_local_sound(user, filename)

    old_path = Path.join(uploads_dir(), filename)
    File.write!(old_path, "audio")
    on_exit(fn -> File.rm(old_path) end)

    {:ok, editor} =
      %User{}
      |> User.changeset(%{
        username: "editor_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    params = %{
      "filename" => "edited_by_other_#{System.unique_integer([:positive])}",
      "source_type" => "local",
      "url" => nil,
      "volume" => "65"
    }

    assert {:ok, updated_sound} = Management.update_sound(sound, editor.id, params)

    new_filename = params["filename"] <> ".mp3"
    new_path = Path.join(uploads_dir(), new_filename)
    on_exit(fn -> File.rm(new_path) end)

    assert updated_sound.filename == new_filename
    assert updated_sound.user_id == user.id
    assert File.exists?(new_path)
    refute File.exists?(old_path)
  end

  test "update_sound/3 ignores internal cooldown changes from non-admin editors", %{user: user} do
    sound = insert_local_sound(user, "cooldown_ignore_#{System.unique_integer([:positive])}.mp3")

    {:ok, editor} =
      %User{}
      |> User.changeset(%{
        username: "non_admin_editor_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    params = %{
      "filename" => Path.basename(sound.filename, Path.extname(sound.filename)),
      "source_type" => "local",
      "url" => nil,
      "volume" => "100",
      "internal_cooldown_seconds" => "45"
    }

    assert {:ok, updated_sound} = Management.update_sound(sound, editor.id, params)
    assert updated_sound.internal_cooldown_seconds == 0
  end

  test "update_sound/3 allows settings admins to change internal cooldown", %{user: user} do
    sound = insert_local_sound(user, "cooldown_admin_#{System.unique_integer([:positive])}.mp3")

    {:ok, admin} =
      %User{}
      |> User.changeset(%{
        username: "cooldown_admin_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    Application.put_env(:soundboard, :discord_settings_admin_user_ids, [admin.discord_id])

    params = %{
      "filename" => Path.basename(sound.filename, Path.extname(sound.filename)),
      "source_type" => "local",
      "url" => nil,
      "volume" => "100",
      "internal_cooldown_seconds" => "45"
    }

    assert {:ok, updated_sound} = Management.update_sound(sound, admin.id, params)
    assert updated_sound.internal_cooldown_seconds == 45
  end

  test "delete_sound/2 is forbidden for non-owner non-admin users", %{user: user} do
    sound = insert_local_sound(user, "locked_#{System.unique_integer([:positive])}.mp3")

    {:ok, intruder} =
      %User{}
      |> User.changeset(%{
        username: "delete_intruder_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    assert {:error, :forbidden} = Management.delete_sound(sound, intruder.id)
    assert Repo.get!(Sound, sound.id)
  end

  test "delete_sound/2 allows settings admins to delete sounds they do not own", %{user: user} do
    sound = insert_local_sound(user, "admin_delete_#{System.unique_integer([:positive])}.mp3")

    {:ok, admin} =
      %User{}
      |> User.changeset(%{
        username: "settings_admin_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    Application.put_env(:soundboard, :discord_settings_admin_user_ids, [admin.discord_id])

    assert :ok = Management.delete_sound(sound, admin)
    assert Repo.get(Sound, sound.id) == nil
  end

  defp insert_local_sound(user, filename) do
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: filename,
        source_type: "local",
        user_id: user.id,
        volume: 1.0
      })
      |> Repo.insert()

    sound
  end

  defp uploads_dir do
    Soundboard.UploadsPath.dir()
  end
end
