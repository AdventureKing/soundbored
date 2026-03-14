defmodule Soundboard.Accounts.PermissionsTest do
  use ExUnit.Case, async: false

  alias Soundboard.Accounts.Permissions
  alias Soundboard.Accounts.User

  setup do
    original_upload_roles = Application.get_env(:soundboard, :discord_upload_role_ids, [])
    original_play_roles = Application.get_env(:soundboard, :discord_play_role_ids, [])

    original_admin_user_ids =
      Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

    on_exit(fn ->
      Application.put_env(:soundboard, :discord_upload_role_ids, original_upload_roles)
      Application.put_env(:soundboard, :discord_play_role_ids, original_play_roles)
      Application.put_env(:soundboard, :discord_settings_admin_user_ids, original_admin_user_ids)
    end)

    :ok
  end

  test "allows uploads by default when no uploader roles are configured" do
    Application.put_env(:soundboard, :discord_upload_role_ids, [])

    user = %User{discord_roles: []}

    assert Permissions.can_upload_clips?(user)
  end

  test "allows uploads when at least one role matches configured uploader roles" do
    Application.put_env(:soundboard, :discord_upload_role_ids, ["role-a", "role-b"])

    user = %User{discord_roles: ["role-z", "role-b"]}

    assert Permissions.can_upload_clips?(user)
  end

  test "denies uploads when roles do not match configured uploader roles" do
    Application.put_env(:soundboard, :discord_upload_role_ids, ["role-a"])

    user = %User{discord_roles: ["role-z"]}

    refute Permissions.can_upload_clips?(user)
  end

  test "denies uploads for missing user when roles are configured" do
    Application.put_env(:soundboard, :discord_upload_role_ids, ["role-a"])

    refute Permissions.can_upload_clips?(nil)
  end

  test "allows play by default when no player roles are configured" do
    Application.put_env(:soundboard, :discord_play_role_ids, [])

    user = %User{discord_roles: []}

    assert Permissions.can_play_clips?(user)
  end

  test "allows play when at least one role matches configured player roles" do
    Application.put_env(:soundboard, :discord_play_role_ids, ["role-play", "role-other"])

    user = %User{discord_roles: ["role-z", "role-play"]}

    assert Permissions.can_play_clips?(user)
  end

  test "denies play when roles do not match configured player roles" do
    Application.put_env(:soundboard, :discord_play_role_ids, ["role-play"])

    user = %User{discord_roles: ["role-z"]}

    refute Permissions.can_play_clips?(user)
  end

  test "denies settings access when admin user IDs are not configured" do
    Application.put_env(:soundboard, :discord_settings_admin_user_ids, [])

    user = %User{discord_id: "1001", discord_roles: []}

    refute Permissions.can_manage_settings?(user)
  end

  test "allows settings access when user has configured admin user ID" do
    Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["1001", "1002"])

    user = %User{discord_id: "1002", discord_roles: ["member"]}

    assert Permissions.can_manage_settings?(user)
  end

  test "denies settings access when user lacks configured admin user ID" do
    Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["1001", "1002"])

    user = %User{discord_id: "9999", discord_roles: ["member"]}

    refute Permissions.can_manage_settings?(user)
  end
end
