defmodule Soundboard.PlaybackCooldownTest do
  use Soundboard.DataCase, async: true

  import Ecto.Query

  alias Soundboard.Accounts.{RoleCooldown, User}
  alias Soundboard.{PlaybackCooldown, Repo, Sound}
  alias Soundboard.Stats.Play

  test "blocks playback while user is still within role cooldown window" do
    user = insert_user(%{discord_roles: ["role-a"]})
    sound = insert_sound(user)

    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-a", cooldown_seconds: 30})
    )

    insert_play(user, sound)

    assert {:error, details} = PlaybackCooldown.check(user)
    assert details.cooldown_seconds == 30
    assert details.remaining_seconds > 0
    assert details.remaining_seconds <= 30
  end

  test "allows playback when last play is older than effective cooldown" do
    user = insert_user(%{discord_roles: ["role-a", "role-b"]})
    sound = insert_sound(user)

    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-a", cooldown_seconds: 60})
    )

    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-b", cooldown_seconds: 15})
    )

    play = insert_play(user, sound)

    old_timestamp = NaiveDateTime.add(NaiveDateTime.utc_now(), -20, :second)
    Repo.update_all(from(p in Play, where: p.id == ^play.id), set: [inserted_at: old_timestamp])

    assert :ok = PlaybackCooldown.check(user)
  end

  test "uses default 10-minute cooldown when role has no configured override" do
    user = insert_user(%{discord_roles: ["role-unset"]})
    sound = insert_sound(user)
    insert_play(user, sound)

    assert {:error, details} = PlaybackCooldown.check(user)
    assert details.cooldown_seconds == 600
    assert details.remaining_seconds > 0
    assert details.remaining_seconds <= 600
  end

  test "returns active cooldown end timestamp in milliseconds when cooldown is active" do
    user = insert_user(%{discord_roles: ["role-a"]})
    sound = insert_sound(user)

    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-a", cooldown_seconds: 30})
    )

    insert_play(user, sound)

    assert is_integer(cooldown_end_ms = PlaybackCooldown.active_cooldown_end_unix_ms(user))
    assert cooldown_end_ms > System.system_time(:millisecond)
  end

  test "returns nil cooldown end timestamp when cooldown has expired" do
    user = insert_user(%{discord_roles: ["role-a"]})
    sound = insert_sound(user)

    Repo.insert!(
      RoleCooldown.changeset(%RoleCooldown{}, %{role_id: "role-a", cooldown_seconds: 15})
    )

    play = insert_play(user, sound)
    old_timestamp = NaiveDateTime.add(NaiveDateTime.utc_now(), -20, :second)
    Repo.update_all(from(p in Play, where: p.id == ^play.id), set: [inserted_at: old_timestamp])

    assert is_nil(PlaybackCooldown.active_cooldown_end_unix_ms(user))
  end

  defp insert_user(attrs) do
    base_attrs = %{
      username: "cooldown_user_#{System.unique_integer([:positive])}",
      discord_id: Integer.to_string(System.unique_integer([:positive])),
      avatar: "cooldown.jpg",
      discord_roles: []
    }

    attrs =
      base_attrs
      |> Map.merge(attrs)

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_sound(user) do
    %Sound{}
    |> Sound.changeset(%{
      filename: "cooldown_sound_#{System.unique_integer([:positive])}.mp3",
      source_type: "local",
      user_id: user.id
    })
    |> Repo.insert!()
  end

  defp insert_play(user, sound) do
    %Play{}
    |> Play.changeset(%{
      played_filename: sound.filename,
      sound_id: sound.id,
      user_id: user.id
    })
    |> Repo.insert!()
  end
end
