defmodule Soundboard.SoundTest do
  @moduledoc """
  Tests the Sound module.
  """
  use Soundboard.DataCase
  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Sound, Sounds, Tag}

  describe "changeset validation" do
    test "validates required fields" do
      changeset = Sound.changeset(%Sound{}, %{})

      assert errors_on(changeset) == %{
               filename: ["can't be blank"],
               user_id: ["can't be blank"]
             }
    end

    test "validates local sound requires filename" do
      changeset =
        Sound.changeset(%Sound{}, %{
          user_id: 1,
          source_type: "local"
        })

      assert "can't be blank" in errors_on(changeset).filename
    end

    test "validates url sound requires url" do
      changeset =
        Sound.changeset(%Sound{}, %{
          user_id: 1,
          source_type: "url"
        })

      assert "can't be blank" in errors_on(changeset).url
    end

    test "validates source type values" do
      changeset =
        Sound.changeset(%Sound{}, %{
          user_id: 1,
          source_type: "invalid"
        })

      assert "must be either 'local' or 'url'" in errors_on(changeset).source_type
    end

    test "enforces unique filenames" do
      user = insert_user()
      attrs = %{filename: "test.mp3", source_type: "local", user_id: user.id}

      {:ok, _} = %Sound{} |> Sound.changeset(attrs) |> Repo.insert()
      {:error, changeset} = %Sound{} |> Sound.changeset(attrs) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).filename
    end

    test "validates volume between 0 and 1.5" do
      user = insert_user()

      high_changeset =
        Sound.changeset(%Sound{}, %{
          filename: "loud.mp3",
          source_type: "local",
          user_id: user.id,
          volume: 1.6
        })

      assert Enum.any?(
               errors_on(high_changeset).volume,
               &String.contains?(&1, "less than or equal")
             )

      low_changeset =
        Sound.changeset(%Sound{}, %{
          filename: "quiet.mp3",
          source_type: "local",
          user_id: user.id,
          volume: -0.1
        })

      assert Enum.any?(
               errors_on(low_changeset).volume,
               &String.contains?(&1, "greater than or equal")
             )
    end

    test "validates internal cooldown is not negative" do
      user = insert_user()

      changeset =
        Sound.changeset(%Sound{}, %{
          filename: "cooldown.mp3",
          source_type: "local",
          user_id: user.id,
          internal_cooldown_seconds: -1
        })

      assert Enum.any?(
               errors_on(changeset).internal_cooldown_seconds,
               &String.contains?(&1, "greater than or equal")
             )
    end

    test "validates duration is not negative" do
      user = insert_user()

      changeset =
        Sound.changeset(%Sound{}, %{
          filename: "duration.mp3",
          source_type: "local",
          user_id: user.id,
          duration_ms: -1
        })

      assert Enum.any?(
               errors_on(changeset).duration_ms,
               &String.contains?(&1, "greater than or equal")
             )
    end
  end

  setup do
    user = insert_user()
    {:ok, tag} = %Tag{name: "test_tag"} |> Tag.changeset(%{}) |> Repo.insert()
    {:ok, sound} = insert_sound(user)
    %{user: user, sound: sound, tag: tag}
  end

  describe "tag associations" do
    test "can associate tags through changeset", %{user: user, tag: tag} do
      attrs = %{
        filename: "test_sound_new.mp3",
        source_type: "local",
        user_id: user.id
      }

      {:ok, sound} =
        %Sound{}
        |> Sound.changeset(attrs)
        |> Repo.insert()

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      sound = Repo.preload(sound, :tags)
      assert [%{name: "test_tag"}] = sound.tags
    end
  end

  describe "queries" do
    test "with_tags/1 preloads tags", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      result = Sound.with_tags() |> Repo.all() |> Enum.find(&(&1.id == sound.id))
      assert [%{name: "test_tag"}] = result.tags
    end

    test "by_tag/2 filters sounds by tag name", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      results = Sound.by_tag("test_tag") |> Repo.all()
      assert length(results) == 1
      assert hd(results).id == sound.id
    end

    test "list_files/0 returns all sounds with tags and settings", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      result = Sounds.list_files() |> Enum.find(&(&1.id == sound.id))
      assert result.id == sound.id
      assert [%{name: "test_tag"}] = result.tags
    end

    test "get_sound!/1 loads all associations", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      result = Sounds.get_sound!(sound.id)
      assert result.id == sound.id
      assert [%{name: "test_tag"}] = result.tags
    end
  end

  describe "fetch_sound_id/1" do
    test "returns sound id when sound exists", %{sound: sound} do
      assert Sounds.fetch_sound_id(sound.filename) == {:ok, sound.id}
    end

    test "returns :error when sound doesn't exist" do
      assert Sounds.fetch_sound_id("nonexistent.mp3") == :error
    end
  end

  describe "fetch_filename_extension/1" do
    test "returns the stored file extension", %{sound: sound} do
      assert Sounds.fetch_filename_extension(sound.id) == {:ok, ".mp3"}
    end

    test "returns :error when sound doesn't exist" do
      assert Sounds.fetch_filename_extension(-1) == :error
    end
  end

  describe "get_recent_uploads/1" do
    test "returns recent uploads with default limit", %{user: user} do
      # Create multiple sounds
      _sounds =
        for _i <- 1..12 do
          {:ok, sound} = insert_sound(user)
          sound
        end

      results = Sounds.get_recent_uploads()

      assert length(results) >= 10

      {filename, username, timestamp} = hd(results)
      assert is_binary(filename)
      assert is_binary(username)
      assert %NaiveDateTime{} = timestamp

      user_results = Enum.filter(results, fn {_, uname, _} -> uname == user.username end)
      assert user_results != []
    end

    test "returns recent uploads with custom limit", %{user: user} do
      # Create 5 sounds
      for _ <- 1..5, do: insert_sound(user)

      results = Sounds.get_recent_uploads(limit: 3)
      assert length(results) == 3
    end

    test "returns empty list when no sounds exist" do
      # Delete all sounds
      Repo.delete_all(Sound)

      results = Sounds.get_recent_uploads()
      assert results == []
    end
  end

  describe "update_sound/2" do
    test "updates sound attributes", %{sound: sound, tag: tag} do
      # Preload tags to avoid association error
      sound = Repo.preload(sound, :tags)

      attrs = %{
        description: "Updated description",
        tags: [tag]
      }

      {:ok, updated_sound} = Sounds.update_sound(sound, attrs)

      assert updated_sound.description == "Updated description"
      assert length(updated_sound.tags) == 1
      assert hd(updated_sound.tags).id == tag.id
    end

    test "validates on update", %{sound: sound} do
      attrs = %{source_type: "invalid"}

      {:error, changeset} = Sounds.update_sound(sound, attrs)
      assert "must be either 'local' or 'url'" in errors_on(changeset).source_type
    end
  end

  describe "changeset with tags" do
    test "associates tags when provided in attrs", %{user: user, tag: tag} do
      attrs = %{
        filename: "tagged_sound.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [tag]
      }

      changeset = Sound.changeset(%Sound{}, attrs)
      assert changeset.valid?

      {:ok, sound} = Repo.insert(changeset)
      sound = Repo.preload(sound, :tags)

      assert length(sound.tags) == 1
      assert hd(sound.tags).id == tag.id
    end

    test "handles empty tags list", %{user: user} do
      attrs = %{
        filename: "no_tags_sound.mp3",
        source_type: "local",
        user_id: user.id,
        tags: []
      }

      changeset = Sound.changeset(%Sound{}, attrs)
      assert changeset.valid?

      {:ok, sound} = Repo.insert(changeset)
      sound = Repo.preload(sound, :tags)

      assert sound.tags == []
    end
  end

  describe "repo persistence" do
    test "can rename sound", %{sound: sound} do
      {:ok, updated_sound} =
        Sound.changeset(sound, %{filename: "renamed_sound.mp3"})
        |> Repo.update()

      assert updated_sound.filename == "renamed_sound.mp3"
      assert updated_sound.id == sound.id
    end

    test "owner can delete sound", %{sound: sound} do
      assert {:ok, _} = Repo.delete(sound)
      refute Repo.get(Sound, sound.id)
    end
  end

  # Helper functions
  defp insert_user do
    {:ok, user} =
      %Soundboard.Accounts.User{}
      |> User.changeset(%{
        username: "test_user_#{System.unique_integer()}",
        discord_id: "123456_#{System.unique_integer()}",
        avatar: "test.jpg"
      })
      |> Repo.insert()

    user
  end

  defp insert_sound(user) do
    %Sound{}
    |> Sound.changeset(%{
      filename: "test_sound_#{System.unique_integer()}.mp3",
      source_type: "local",
      user_id: user.id
    })
    |> Repo.insert()
  end
end
