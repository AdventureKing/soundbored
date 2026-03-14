defmodule Soundboard.ClipCooldownTest do
  use Soundboard.DataCase, async: true

  import Ecto.Query

  alias Soundboard.Accounts.User
  alias Soundboard.{ClipCooldown, Repo, Sound}
  alias Soundboard.Stats.Play

  test "blocks playback when sound is within its internal cooldown window" do
    user = insert_user()
    other_user = insert_user()
    sound = insert_sound(user, 30)

    insert_play(other_user, sound)

    assert {:error, details} = ClipCooldown.check(sound.filename)
    assert details.cooldown_seconds == 30
    assert details.remaining_seconds > 0
    assert details.remaining_seconds <= 30
  end

  test "allows playback when internal cooldown is disabled" do
    user = insert_user()
    other_user = insert_user()
    sound = insert_sound(user, 0)

    insert_play(other_user, sound)

    assert :ok = ClipCooldown.check(sound)
  end

  test "allows playback after internal cooldown has expired" do
    user = insert_user()
    other_user = insert_user()
    sound = insert_sound(user, 5)

    play = insert_play(other_user, sound)
    old_timestamp = NaiveDateTime.add(NaiveDateTime.utc_now(), -10, :second)
    Repo.update_all(from(p in Play, where: p.id == ^play.id), set: [inserted_at: old_timestamp])

    assert :ok = ClipCooldown.check(sound.filename)
  end

  defp insert_user do
    %User{}
    |> User.changeset(%{
      username: "clip_user_#{System.unique_integer([:positive])}",
      discord_id: Integer.to_string(System.unique_integer([:positive])),
      avatar: "clip.jpg",
      discord_roles: []
    })
    |> Repo.insert!()
  end

  defp insert_sound(user, cooldown_seconds) do
    %Sound{}
    |> Sound.changeset(%{
      filename: "clip_sound_#{System.unique_integer([:positive])}.mp3",
      source_type: "local",
      user_id: user.id,
      internal_cooldown_seconds: cooldown_seconds
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
