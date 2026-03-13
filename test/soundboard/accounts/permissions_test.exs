defmodule Soundboard.Accounts.PermissionsTest do
  use ExUnit.Case, async: false

  alias Soundboard.Accounts.Permissions
  alias Soundboard.Accounts.User

  setup do
    original = Application.get_env(:soundboard, :discord_upload_role_ids, [])

    on_exit(fn ->
      Application.put_env(:soundboard, :discord_upload_role_ids, original)
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
end
