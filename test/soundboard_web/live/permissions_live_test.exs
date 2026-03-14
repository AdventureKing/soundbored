defmodule SoundboardWeb.PermissionsLiveTest do
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Soundboard.Accounts.User
  alias Soundboard.Repo

  setup %{conn: conn} do
    original_upload_roles = Application.get_env(:soundboard, :discord_upload_role_ids, [])
    original_play_roles = Application.get_env(:soundboard, :discord_play_role_ids, [])

    original_admin_user_ids =
      Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

    Application.put_env(:soundboard, :discord_upload_role_ids, ["uploader-role"])
    Application.put_env(:soundboard, :discord_play_role_ids, ["player-role"])
    Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["settings-admin-user"])

    on_exit(fn ->
      Application.put_env(:soundboard, :discord_upload_role_ids, original_upload_roles)
      Application.put_env(:soundboard, :discord_play_role_ids, original_play_roles)
      Application.put_env(:soundboard, :discord_settings_admin_user_ids, original_admin_user_ids)
    end)

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "permissions_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg",
        discord_roles: ["member", "uploader-role"]
      })
      |> Repo.insert()

    authed_conn =
      conn
      |> Map.replace!(:secret_key_base, SoundboardWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_id: user.id})

    %{conn: authed_conn, user: user}
  end

  test "shows play, upload, and settings permission sections", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/permissions")

    assert html =~ "Permissions"
    assert html =~ "Clip Playback"
    assert html =~ "Clip Upload"
    assert html =~ "Settings Access"
  end

  test "allows opening permissions page for non-admin users", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/permissions")

    assert html =~ "Clip Playback"
    assert html =~ "Allowed player role IDs:"
    assert html =~ "Not allowed"
    assert html =~ "Clip Upload"
    assert html =~ "Allowed uploader role IDs:"
    assert html =~ "Allowed"
    assert html =~ "Settings Access"
  end
end
