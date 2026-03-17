defmodule SoundboardWeb.SoundboardLiveTest do
  @moduledoc false
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Soundboard.{Accounts.User, Favorites, Repo, Sound, Tag}
  import Mock

  setup %{conn: conn} do
    Repo.delete_all(Sound)
    Repo.delete_all(User)

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser",
        discord_id: "123",
        avatar: "test.jpg"
      })
      |> Repo.insert()

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert()

    conn = conn |> init_test_session(%{user_id: user.id})

    {:ok, conn: conn, user: user, sound: sound}
  end

  describe "Soundboard LiveView" do
    test "mounts successfully with user session", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      assert html =~ "Sounds"
      # Check for the main content instead of a specific container
      assert html =~ "BeeBot"
      assert html =~ "Cooldown"
      assert html =~ "sidebar-cooldown-desktop"
      assert render(view) =~ "clip-duration"
    end

    test "can search sounds", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("form")
      |> render_change(%{"query" => "test"})

      rendered = render(view)
      assert rendered =~ "test.mp3"
    end

    test "can clear search query from find sounds", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      refute has_element?(view, "button[phx-click='clear_search']")

      view
      |> element("form")
      |> render_change(%{"query" => "test"})

      assert has_element?(view, "input[name='query'][value='test']")
      assert has_element?(view, "button[phx-click='clear_search']")

      view
      |> element("button[phx-click='clear_search']")
      |> render_click()

      assert has_element?(view, "input[name='query'][value='']")
      refute has_element?(view, "button[phx-click='clear_search']")
    end

    test "can play sound", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      with_mock Soundboard.AudioPlayer, play_sound: fn _, _ -> :ok end do
        rendered =
          view
          |> element("[phx-click='play'][phx-value-name='#{sound.filename}']")
          |> render_click()

        assert rendered =~ sound.filename
      end
    end

    test "play random respects current search results", %{conn: conn, user: user} do
      %Sound{}
      |> Sound.changeset(%{
        filename: "filtered.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("form")
      |> render_change(%{"query" => "filtered"})

      with_mock Soundboard.AudioPlayer, play_sound: fn _, _ -> :ok end do
        view
        |> element("[phx-click='play_random']")
        |> render_click()

        assert_called(Soundboard.AudioPlayer.play_sound("filtered.mp3", :_))
      end
    end

    test "play random respects selected tags", %{conn: conn, user: user} do
      tag =
        %Tag{}
        |> Tag.changeset(%{name: "funny"})
        |> Repo.insert!()

      %Sound{}
      |> Sound.changeset(%{
        filename: "funny.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [tag]
      })
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("#tag-filter-panel button[phx-value-tag='funny']")
      |> render_click()

      with_mock Soundboard.AudioPlayer, play_sound: fn _, _ -> :ok end do
        view
        |> element("[phx-click='play_random']")
        |> render_click()

        assert_called(Soundboard.AudioPlayer.play_sound("funny.mp3", :_))
      end
    end

    test "can select and filter by multiple tags", %{conn: conn, user: user} do
      alpha =
        %Tag{}
        |> Tag.changeset(%{name: "alpha"})
        |> Repo.insert!()

      beta =
        %Tag{}
        |> Tag.changeset(%{name: "beta"})
        |> Repo.insert!()

      %Sound{}
      |> Sound.changeset(%{
        filename: "alpha-only.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [alpha]
      })
      |> Repo.insert!()

      %Sound{}
      |> Sound.changeset(%{
        filename: "beta-only.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [beta]
      })
      |> Repo.insert!()

      %Sound{}
      |> Sound.changeset(%{
        filename: "alpha-beta.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [alpha, beta]
      })
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='set_tag_filter_mode'][phx-value-mode='and']")
      |> render_click()

      view
      |> element("#tag-filter-panel button[phx-value-tag='alpha']")
      |> render_click()

      assert has_element?(view, "[phx-click='play'][phx-value-name='alpha-only.mp3']")
      assert has_element?(view, "[phx-click='play'][phx-value-name='alpha-beta.mp3']")
      refute has_element?(view, "[phx-click='play'][phx-value-name='beta-only.mp3']")

      view
      |> element("#tag-filter-panel button[phx-value-tag='beta']")
      |> render_click()

      refute has_element?(view, "[phx-click='play'][phx-value-name='alpha-only.mp3']")
      assert has_element?(view, "[phx-click='play'][phx-value-name='alpha-beta.mp3']")
      refute has_element?(view, "[phx-click='play'][phx-value-name='beta-only.mp3']")

      rendered = render(view)
      assert rendered =~ "Active filter:"
      assert rendered =~ "alpha, beta"

      view
      |> element("#tag-filter-panel button[phx-value-tag='alpha']")
      |> render_click()

      refute has_element?(view, "[phx-click='play'][phx-value-name='alpha-only.mp3']")
      assert has_element?(view, "[phx-click='play'][phx-value-name='alpha-beta.mp3']")
      assert has_element?(view, "[phx-click='play'][phx-value-name='beta-only.mp3']")
    end

    test "favorites toggle filters to only favorited sounds", %{
      conn: conn,
      user: user,
      sound: sound
    } do
      %Sound{}
      |> Sound.changeset(%{
        filename: "not-favorited.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert!()

      {:ok, _favorite} = Favorites.toggle_favorite(user.id, sound.id)

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "[phx-click='play'][phx-value-name='#{sound.filename}']")
      assert has_element?(view, "[phx-click='play'][phx-value-name='not-favorited.mp3']")

      view
      |> element("#favorites-filter-toggle")
      |> render_click()

      assert has_element?(view, "[phx-click='play'][phx-value-name='#{sound.filename}']")
      refute has_element?(view, "[phx-click='play'][phx-value-name='not-favorited.mp3']")

      view
      |> element("#favorites-filter-toggle")
      |> render_click()

      assert has_element?(view, "[phx-click='play'][phx-value-name='#{sound.filename}']")
      assert has_element?(view, "[phx-click='play'][phx-value-name='not-favorited.mp3']")
    end

    test "tag filters still work while favorites filter is enabled", %{conn: conn, user: user} do
      alpha =
        %Tag{}
        |> Tag.changeset(%{name: "fav-alpha"})
        |> Repo.insert!()

      beta =
        %Tag{}
        |> Tag.changeset(%{name: "fav-beta"})
        |> Repo.insert!()

      favorite_sound =
        %Sound{}
        |> Sound.changeset(%{
          filename: "fav-alpha-beta.mp3",
          source_type: "local",
          user_id: user.id,
          tags: [alpha, beta]
        })
        |> Repo.insert!()

      %Sound{}
      |> Sound.changeset(%{
        filename: "nonfav-alpha-beta.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [alpha, beta]
      })
      |> Repo.insert!()

      {:ok, _favorite} = Favorites.toggle_favorite(user.id, favorite_sound.id)

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("#favorites-filter-toggle")
      |> render_click()

      assert has_element?(view, "[phx-click='play'][phx-value-name='fav-alpha-beta.mp3']")
      refute has_element?(view, "[phx-click='play'][phx-value-name='nonfav-alpha-beta.mp3']")

      view
      |> element("#tag-filter-panel button[phx-value-tag='fav-alpha']")
      |> render_click()

      view
      |> element("#tag-filter-panel button[phx-value-tag='fav-beta']")
      |> render_click()

      assert has_element?(view, "[phx-click='play'][phx-value-name='fav-alpha-beta.mp3']")
      refute has_element?(view, "[phx-click='play'][phx-value-name='nonfav-alpha-beta.mp3']")
    end

    test "shows featured tags above regular tag filters", %{conn: conn, user: user} do
      featured_tag =
        %Tag{}
        |> Tag.changeset(%{name: "featured", featured: true})
        |> Repo.insert!()

      %Sound{}
      |> Sound.changeset(%{
        filename: "featured.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [featured_tag]
      })
      |> Repo.insert!()

      {:ok, view, html} = live(conn, "/")

      assert html =~ "Featured Tags"
      assert has_element?(view, "#featured-tag-panel button[phx-value-tag='featured']")
    end

    test "shows admin stop and clear queue button for settings admins", %{conn: conn, user: user} do
      original_admin_user_ids =
        Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

      Application.put_env(:soundboard, :discord_settings_admin_user_ids, [user.discord_id])

      on_exit(fn ->
        Application.put_env(
          :soundboard,
          :discord_settings_admin_user_ids,
          original_admin_user_ids
        )
      end)

      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Admin Stop + Clear Queue"
      refute html =~ "Stop All"
    end

    test "hides admin stop and clear queue button for non-admins", %{conn: conn} do
      original_admin_user_ids =
        Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

      Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["different-admin"])

      on_exit(fn ->
        Application.put_env(
          :soundboard,
          :discord_settings_admin_user_ids,
          original_admin_user_ids
        )
      end)

      {:ok, _view, html} = live(conn, "/")

      refute html =~ "Admin Stop + Clear Queue"
      refute html =~ "Stop All"
    end

    test "admin stop and clear queue button clears playback queue", %{conn: conn, user: user} do
      original_admin_user_ids =
        Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

      Application.put_env(:soundboard, :discord_settings_admin_user_ids, [user.discord_id])

      on_exit(fn ->
        Application.put_env(
          :soundboard,
          :discord_settings_admin_user_ids,
          original_admin_user_ids
        )
      end)

      {:ok, view, _html} = live(conn, "/")

      with_mock Soundboard.AudioPlayer, stop_and_clear_queue: fn -> :ok end do
        view
        |> element("[phx-click='admin_stop_and_clear_queue']")
        |> render_click()

        assert_called(Soundboard.AudioPlayer.stop_and_clear_queue())
      end
    end

    test "can open and close upload modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # First verify we can see the Add Sound button
      assert render(view) =~ "Add Sound"

      # Click the Add Sound button and verify modal appears
      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      # The modal should be visible now, verify its presence using form ID and content
      assert has_element?(view, "#upload-form")
      assert has_element?(view, "form[phx-submit='save_upload']")
      assert has_element?(view, "select[name='source_type']")
      assert render(view) =~ "Source Type"

      # Close the modal using the correct phx-click value
      view
      |> element("[phx-click='close_upload_modal']")
      |> render_click()

      # Verify modal is gone by checking for the form
      refute has_element?(view, "#upload-form")
    end

    test "disables Add Sound when uploader role is missing", %{conn: conn} do
      original = Application.get_env(:soundboard, :discord_upload_role_ids, [])
      Application.put_env(:soundboard, :discord_upload_role_ids, ["role-required"])

      on_exit(fn ->
        Application.put_env(:soundboard, :discord_upload_role_ids, original)
      end)

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "button[disabled]", "Add Sound")
      refute has_element?(view, "button[phx-click='show_upload_modal']")
    end

    test "can edit sound", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      rendered =
        view
        |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
        |> render_click()

      assert rendered =~ "Edit Sound"

      params = %{
        "filename" => "updated",
        "source_type" => "local",
        "volume" => "80"
      }

      uploads_dir = uploads_dir()
      File.mkdir_p!(uploads_dir)

      test_file = Path.join(uploads_dir, "test.mp3")
      updated_file = Path.join(uploads_dir, "updated.mp3")

      unless File.exists?(test_file) do
        File.write!(test_file, "test content")
      end

      # Target the edit form specifically
      view
      |> element("#edit-form")
      |> render_submit(params)

      # Clean up both original and updated files
      File.rm_rf!(test_file)
      File.rm_rf!(updated_file)

      updated_sound = Repo.get(Sound, sound.id)
      assert updated_sound.filename == "updated.mp3"
      assert_in_delta updated_sound.volume, 0.8, 0.0001
    end

    test "hides edit button for sounds uploaded by others when viewer is not an admin", %{
      conn: conn,
      sound: sound
    } do
      original_admin_user_ids =
        Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

      Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["different-admin"])

      on_exit(fn ->
        Application.put_env(
          :soundboard,
          :discord_settings_admin_user_ids,
          original_admin_user_ids
        )
      end)

      {:ok, other_user} =
        %User{}
        |> User.changeset(%{
          username: "other_non_admin_#{System.unique_integer([:positive])}",
          discord_id: Integer.to_string(System.unique_integer([:positive])),
          avatar: "other.jpg"
        })
        |> Repo.insert()

      {:ok, other_sound} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "other-non-admin-owned.mp3",
          source_type: "local",
          user_id: other_user.id
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "[phx-click='edit'][phx-value-id='#{sound.id}']")
      refute has_element?(view, "[phx-click='edit'][phx-value-id='#{other_sound.id}']")
    end

    test "settings admins can edit and delete sounds uploaded by others", %{
      conn: conn,
      user: user
    } do
      original_admin_user_ids =
        Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

      Application.put_env(:soundboard, :discord_settings_admin_user_ids, [user.discord_id])

      on_exit(fn ->
        Application.put_env(
          :soundboard,
          :discord_settings_admin_user_ids,
          original_admin_user_ids
        )
      end)

      {:ok, other_user} =
        %User{}
        |> User.changeset(%{
          username: "other_#{System.unique_integer([:positive])}",
          discord_id: Integer.to_string(System.unique_integer([:positive])),
          avatar: "other.jpg"
        })
        |> Repo.insert()

      {:ok, other_sound} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "other-owned.mp3",
          source_type: "local",
          user_id: other_user.id
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "[phx-click='edit'][phx-value-id='#{other_sound.id}']")

      rendered =
        view
        |> element("[phx-click='edit'][phx-value-id='#{other_sound.id}']")
        |> render_click()

      assert rendered =~ "Edit Sound"
      assert rendered =~ "Delete Sound"

      view
      |> element("[phx-click='show_delete_confirm']")
      |> render_click()

      view
      |> element("[phx-click='delete_sound']")
      |> render_click()

      assert Repo.get(Sound, other_sound.id) == nil
    end

    test "edit validation preserves the current sound extension when checking duplicates", %{
      conn: conn,
      user: user
    } do
      {:ok, current_sound} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "current.wav",
          source_type: "local",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, _existing_sound} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "taken.wav",
          source_type: "local",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='edit'][phx-value-id='#{current_sound.id}']")
      |> render_click()

      view
      |> element("#edit-form")
      |> render_change(%{
        "_target" => ["filename"],
        "sound_id" => current_sound.id,
        "filename" => "taken"
      })

      assert render(view) =~ "A sound with that name already exists"
    end

    test "slider volume change persists on save", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
      |> render_click()

      render_hook(view, :update_volume, %{"volume" => 27, "target" => "edit"})

      base_filename = Path.rootname(sound.filename)

      view
      |> element("#edit-form")
      |> render_submit(%{
        "filename" => base_filename,
        "source_type" => sound.source_type,
        "volume" => "27"
      })

      updated_sound = Repo.get!(Sound, sound.id)
      assert_in_delta updated_sound.volume, 0.27, 0.0001
    end

    test "can delete sound", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      uploads_dir = uploads_dir()
      test_file = Path.join(uploads_dir, "test.mp3")
      File.mkdir_p!(uploads_dir)
      File.write!(test_file, "test content")

      view
      |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
      |> render_click()

      view
      |> element("[phx-click='show_delete_confirm']")
      |> render_click()

      view
      |> element("[phx-click='delete_sound']")
      |> render_click()

      File.rm_rf!(test_file)

      assert Repo.get(Sound, sound.id) == nil
    end

    test "url upload allows setting url before name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      view
      |> element("select[name='source_type']")
      |> render_change(%{"source_type" => "url"})

      html =
        view
        |> element("#upload-form")
        |> render_change(%{"url" => "https://example.com/beep.mp3"})

      refute html =~ "Please select a file"
      refute html =~ "can't be blank"
      assert html =~ "https://example.com/beep.mp3"
    end

    test "can upload sound from url", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      view
      |> element("select[name='source_type']")
      |> render_change(%{"source_type" => "url"})

      params = %{
        "url" => "https://example.com/wow.mp3",
        "name" => "wow",
        "upload_tag_input" => "meme"
      }

      view
      |> element("#upload-form")
      |> render_submit(params)

      new_sound = Repo.get_by!(Sound, filename: "wow.mp3")
      assert new_sound.source_type == "url"
      assert new_sound.url == "https://example.com/wow.mp3"
      assert new_sound.user_id == user.id

      Repo.delete!(new_sound)
    end

    test "url upload accepts a single tag still in the input", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      view
      |> element("select[name='source_type']")
      |> render_change(%{"source_type" => "url"})

      unique = System.unique_integer([:positive])
      sound_name = "single-tag-#{unique}"
      url = "https://example.com/#{sound_name}.mp3"
      tag_name = "one-tag-#{unique}"

      view
      |> element("#upload-form")
      |> render_submit(%{
        "url" => url,
        "name" => sound_name,
        "upload_tag_input" => tag_name
      })

      sound =
        Sound
        |> Repo.get_by!(filename: "#{sound_name}.mp3")
        |> Repo.preload(:tags)

      assert sound.source_type == "url"
      assert sound.url == url
      assert sound.user_id == user.id
      assert Enum.any?(sound.tags, &(&1.name == tag_name))

      Repo.delete!(sound)
    end

    test "upload sound from url saves provided volume", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      view
      |> element("select[name='source_type']")
      |> render_change(%{"source_type" => "url"})

      view
      |> element("#upload-form")
      |> render_submit(%{
        "url" => "https://example.com/soft.mp3",
        "name" => "soft",
        "volume" => "25",
        "upload_tag_input" => "quiet"
      })

      sound = Repo.get_by!(Sound, filename: "soft.mp3")
      assert_in_delta sound.volume, 0.25, 0.0001

      Repo.delete!(sound)
    end

    test "deleting a local sound removes the file", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      uploads_dir = uploads_dir()
      File.mkdir_p!(uploads_dir)
      sound_path = Path.join(uploads_dir, sound.filename)
      File.write!(sound_path, "test content")

      view
      |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
      |> render_click()

      view
      |> element("[phx-click='show_delete_confirm']")
      |> render_click()

      view
      |> element("[phx-click='delete_sound']")
      |> render_click()

      refute File.exists?(sound_path)
      assert Repo.get(Sound, sound.id) == nil
    end

    test "failed rename keeps original file", %{conn: conn, user: user, sound: sound} do
      {:ok, conflict_sound} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "conflict.mp3",
          source_type: "local",
          user_id: user.id
        })
        |> Repo.insert()

      uploads_dir = uploads_dir()
      File.mkdir_p!(uploads_dir)

      original_path = Path.join(uploads_dir, sound.filename)
      conflict_path = Path.join(uploads_dir, conflict_sound.filename)

      File.write!(original_path, "original")
      File.rm_rf!(conflict_path)

      on_exit(fn ->
        uploads_dir = uploads_dir()
        File.rm_rf!(Path.join(uploads_dir, sound.filename))
        File.rm_rf!(Path.join(uploads_dir, "conflict.mp3"))
      end)

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
      |> render_click()

      _html =
        view
        |> element("#edit-form")
        |> render_submit(%{
          "filename" => "conflict",
          "source_type" => "local",
          "url" => "",
          "sound_id" => Integer.to_string(sound.id)
        })

      assert File.exists?(original_path)
      refute File.exists?(conflict_path)
      assert Repo.get!(Sound, sound.id).filename == sound.filename
    end

    test "handles pubsub updates", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      Soundboard.PubSubTopics.broadcast_files_updated()

      # Just verify the view is still alive
      assert render(view) =~ "BeeBot"
    end
  end

  defp uploads_dir do
    Soundboard.UploadsPath.dir()
  end
end
