defmodule Soundboard.Accounts.RoleCooldownsTest do
  use Soundboard.DataCase, async: true

  alias Soundboard.Accounts.{RoleCooldown, RoleCooldowns, User}
  alias Soundboard.Repo

  test "effective_cooldown_seconds chooses the lowest configured role cooldown" do
    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-a", cooldown_seconds: 30})
    )

    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-b", cooldown_seconds: 10})
    )

    user = %User{discord_roles: ["role-z", "role-a", "role-b"]}

    assert RoleCooldowns.effective_cooldown_seconds(user) == 10
  end

  test "effective_cooldown_seconds defaults to 10 minutes when role has no override" do
    user = %User{discord_roles: ["role-z"]}
    assert RoleCooldowns.effective_cooldown_seconds(user) == 600
  end

  test "effective_cooldown_seconds still applies default for unconfigured roles" do
    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-slow", cooldown_seconds: 900})
    )

    user = %User{discord_roles: ["role-slow", "role-unset"]}

    assert RoleCooldowns.effective_cooldown_seconds(user) == 600
  end

  test "replace_for_roles upserts and clears cooldowns" do
    assert :ok =
             RoleCooldowns.replace_for_roles(["role-a", "role-b"], %{
               "role-a" => "20",
               "role-b" => ""
             })

    assert Repo.get_by(RoleCooldown, role_id: "role-a").cooldown_seconds == 20
    assert Repo.get_by(RoleCooldown, role_id: "role-b") == nil

    assert :ok = RoleCooldowns.replace_for_roles(["role-a"], %{"role-a" => "0"})
    assert Repo.get_by(RoleCooldown, role_id: "role-a") == nil
  end

  test "replace_for_roles rejects invalid cooldown values and rolls back changes" do
    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-a", cooldown_seconds: 15})
    )

    assert {:error, {:invalid_cooldown, _}} =
             RoleCooldowns.replace_for_roles(["role-a", "role-b"], %{
               "role-a" => "25",
               "role-b" => "nope"
             })

    assert Repo.get_by(RoleCooldown, role_id: "role-a").cooldown_seconds == 15
    assert Repo.get_by(RoleCooldown, role_id: "role-b") == nil
  end
end
