defmodule SoundboardWeb.SettingsLiveTest do
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  import Mock
  alias Soundboard.Accounts.{ApiTokens, RoleCooldown, User}
  alias Soundboard.Repo

  setup %{conn: conn} do
    original_admin_user_ids =
      Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

    on_exit(fn ->
      Application.put_env(:soundboard, :discord_settings_admin_user_ids, original_admin_user_ids)
    end)

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "apitok_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg",
        discord_roles: ["member"]
      })
      |> Repo.insert()

    Application.put_env(:soundboard, :discord_settings_admin_user_ids, [user.discord_id])

    authed_conn =
      conn
      |> Map.replace!(:secret_key_base, SoundboardWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_id: user.id})

    %{conn: authed_conn, user: user}
  end

  test "can create and revoke tokens via live view", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    # Create token
    view
    |> element("form[phx-submit=\"create_token\"]")
    |> render_submit(%{"label" => "CI Bot"})

    # Ensure it appears in the table
    html = render(view)
    assert html =~ "CI Bot"

    # Revoke the first token button
    view
    |> element("button", "Revoke")
    |> render_click()

    # Should disappear from the table
    refute has_element?(view, "td", "CI Bot")
  end

  test "shows persisted tokens after reload", %{conn: conn, user: user} do
    {:ok, raw, _token} = ApiTokens.generate_token(user, %{label: "Saved token"})

    {:ok, _view, html} = live(conn, "/settings")

    assert html =~ "Saved token"
    assert html =~ raw
  end

  test "shows upload API documentation", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings")

    assert html =~ "POST /api/sounds"
    assert html =~ "Upload local file (multipart/form-data)"
    assert html =~ "Upload from URL (JSON)"
    assert html =~ "tags[]"
    assert html =~ "is_join_sound"
    assert html =~ "is_leave_sound"
  end

  test "lists role cooldown rows alphabetically and saves per-role cooldowns", %{conn: conn} do
    guilds = [
      %{
        id: "guild-1",
        name: "Guild One",
        channels: %{},
        voice_states: [],
        roles: [
          %{id: "role-charlie", name: "Charlie Role", position: 10},
          %{id: "role-alpha", name: "Alpha Role", position: 5},
          %{id: "role-bravo", name: "Bravo Role", position: 1}
        ]
      }
    ]

    with_mock Soundboard.Discord.GuildCache, all: fn -> guilds end do
      {:ok, view, html} = live(conn, "/settings")

      assert html =~ "Role Cooldowns"
      assert html =~ ~r/Alpha Role.*Bravo Role.*Charlie Role/s

      view
      |> element("form[phx-submit=\"save_role_cooldowns\"]")
      |> render_submit(%{
        "cooldowns" => %{
          "role-alpha" => "5",
          "role-bravo" => "30",
          "role-charlie" => "60"
        }
      })
    end

    assert Repo.get_by(RoleCooldown, role_id: "role-alpha").cooldown_seconds == 5
    assert Repo.get_by(RoleCooldown, role_id: "role-bravo").cooldown_seconds == 30
    assert Repo.get_by(RoleCooldown, role_id: "role-charlie").cooldown_seconds == 60
  end

  test "filters role cooldown rows and preserves hidden cooldowns on save", %{conn: conn} do
    guilds = [
      %{
        id: "guild-1",
        name: "Guild One",
        channels: %{},
        voice_states: [],
        roles: [
          %{id: "role-alpha", name: "Alpha Role", position: 10},
          %{id: "role-beta", name: "Beta Role", position: 5}
        ]
      }
    ]

    %RoleCooldown{}
    |> RoleCooldown.changeset(%{role_id: "role-beta", cooldown_seconds: 45})
    |> Repo.insert!()

    with_mock Soundboard.Discord.GuildCache, all: fn -> guilds end do
      {:ok, view, _html} = live(conn, "/settings")

      view
      |> element("form[phx-change=\"filter_role_cooldowns\"]")
      |> render_change(%{"role_filter" => %{"query" => "Alpha"}})

      filtered_html = render(view)
      assert filtered_html =~ "Alpha Role"
      refute filtered_html =~ "Beta Role"

      view
      |> element("form[phx-submit=\"save_role_cooldowns\"]")
      |> render_submit(%{"cooldowns" => %{"role-alpha" => "15"}})
    end

    assert Repo.get_by(RoleCooldown, role_id: "role-alpha").cooldown_seconds == 15
    assert Repo.get_by(RoleCooldown, role_id: "role-beta").cooldown_seconds == 45
  end

  test "toggles role cooldown table sort direction from header clicks", %{conn: conn} do
    guilds = [
      %{
        id: "guild-1",
        name: "Guild One",
        channels: %{},
        voice_states: [],
        roles: [
          %{id: "role-charlie", name: "Charlie Role", position: 10},
          %{id: "role-alpha", name: "Alpha Role", position: 5},
          %{id: "role-bravo", name: "Bravo Role", position: 1}
        ]
      }
    ]

    with_mock Soundboard.Discord.GuildCache, all: fn -> guilds end do
      {:ok, view, html} = live(conn, "/settings")
      assert html =~ ~r/Alpha Role.*Bravo Role.*Charlie Role/s

      view
      |> element("button[phx-click=\"sort_role_cooldowns\"][phx-value-field=\"role_name\"]")
      |> render_click()

      descending_html = render(view)
      assert descending_html =~ ~r/Charlie Role.*Bravo Role.*Alpha Role/s

      view
      |> element("button[phx-click=\"sort_role_cooldowns\"][phx-value-field=\"role_name\"]")
      |> render_click()

      ascending_html = render(view)
      assert ascending_html =~ ~r/Alpha Role.*Bravo Role.*Charlie Role/s
    end
  end

  test "redirects when user is missing configured settings admin user ID", %{conn: conn} do
    {:ok, non_admin} =
      %User{}
      |> User.changeset(%{
        username: "non_admin_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "non-admin.jpg",
        discord_roles: ["member"]
      })
      |> Repo.insert()

    non_admin_conn =
      conn
      |> recycle()
      |> Map.replace!(:secret_key_base, SoundboardWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_id: non_admin.id})

    assert {:error, {:redirect, %{to: "/"}}} = live(non_admin_conn, "/settings")
  end
end
