defmodule SoundboardWeb.Components.Soundboard.EditModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SoundboardWeb.Components.Soundboard.EditModal

  setup do
    original_admin_user_ids =
      Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

    on_exit(fn ->
      Application.put_env(:soundboard, :discord_settings_admin_user_ids, original_admin_user_ids)
    end)

    :ok
  end

  test "renders edit form with local file metadata" do
    html = render_component(&EditModal.edit_modal/1, edit_assigns())

    assert html =~ "Edit Sound"
    assert html =~ "Local File"
    assert html =~ "Save Changes"
    assert html =~ "Delete Sound"
  end

  test "renders source URL and edit validation errors" do
    html =
      render_component(
        &EditModal.edit_modal/1,
        edit_assigns(%{
          current_sound: %{
            edit_sound()
            | source_type: "url",
              url: "https://example.com/sound.mp3"
          },
          edit_name_error: "Name already taken"
        })
      )

    assert html =~ "URL: https://example.com/sound.mp3"
    assert html =~ "Name already taken"
  end

  test "hides delete for non-owners" do
    html =
      render_component(
        &EditModal.edit_modal/1,
        edit_assigns(%{
          current_user: %{id: 2}
        })
      )

    refute html =~ "Delete Sound"
  end

  test "shows internal cooldown input for settings admins only" do
    Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["admin-user-id"])

    admin_html =
      render_component(
        &EditModal.edit_modal/1,
        edit_assigns(%{
          current_user: %{id: 2, discord_id: "admin-user-id"}
        })
      )

    user_html =
      render_component(
        &EditModal.edit_modal/1,
        edit_assigns(%{
          current_user: %{id: 1, discord_id: "regular-user-id"}
        })
      )

    assert admin_html =~ "Internal Cooldown (seconds)"
    refute user_html =~ "Internal Cooldown (seconds)"
  end

  test "shows delete for settings admins even when they are not the owner" do
    Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["admin-user-id"])

    html =
      render_component(
        &EditModal.edit_modal/1,
        edit_assigns(%{
          current_user: %{id: 2, discord_id: "admin-user-id"}
        })
      )

    assert html =~ "Delete Sound"
  end

  defp edit_assigns(overrides \\ %{}) do
    base = %{
      current_sound: edit_sound(),
      current_user: %{id: 1},
      tag_input: "",
      tag_suggestions: [],
      edit_name_error: nil,
      flash: %{}
    }

    Map.merge(base, overrides)
  end

  defp edit_sound do
    %{
      id: 10,
      filename: "laser.mp3",
      source_type: "local",
      url: nil,
      volume: 1.0,
      internal_cooldown_seconds: 0,
      tags: [%{name: "funny"}],
      user_id: 1,
      user_sound_settings: [%{user_id: 1, is_join_sound: true, is_leave_sound: false}]
    }
  end
end
