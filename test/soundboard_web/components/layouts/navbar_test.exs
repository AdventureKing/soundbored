defmodule SoundboardWeb.Components.Layouts.NavbarTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias SoundboardWeb.Components.Layouts.Navbar

  setup do
    original_admin_role = Application.get_env(:soundboard, :discord_settings_admin_role_id)

    on_exit(fn ->
      Application.put_env(:soundboard, :discord_settings_admin_role_id, original_admin_role)
    end)

    :ok
  end

  test "renders public navigation links" do
    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/",
        current_user: nil,
        presences: %{}
      )

    assert html =~ "SoundBored"
    assert html =~ "Sounds"
    assert html =~ "Favorites"
    assert html =~ "Stats"
    refute html =~ "Permissions"
    refute html =~ "Settings"
  end

  test "renders permissions/settings links and deduplicated presences for admin users" do
    Application.put_env(:soundboard, :discord_settings_admin_role_id, "settings-admin")

    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/settings",
        current_user: %{id: 1, username: "owner", discord_roles: ["settings-admin"]},
        presences: %{
          "1" => %{metas: [%{user: %{username: "alice", avatar: "alice.png"}}]},
          "2" => %{metas: [%{user: %{username: "alice", avatar: "alice.png"}}]},
          "3" => %{metas: [%{user: %{username: "bob", avatar: "bob.png"}}]}
        }
      )

    assert html =~ "Permissions"
    assert html =~ "Settings"
    assert html =~ "user-alice"
    assert html =~ "user-bob"

    # Duplicated presence entries for the same user should only render once per menu section.
    assert length(Regex.scan(~r/user-alice/, html)) == 2
  end

  test "toggle-mobile-menu flips show_mobile_menu assign" do
    {:ok, socket} = Navbar.mount(%Phoenix.LiveView.Socket{})

    {:noreply, socket} = Navbar.handle_event("toggle-mobile-menu", %{}, socket)
    assert socket.assigns.show_mobile_menu

    {:noreply, socket} = Navbar.handle_event("toggle-mobile-menu", %{}, socket)
    refute socket.assigns.show_mobile_menu
  end

  test "hides settings link when admin role is configured and user does not have it" do
    Application.put_env(:soundboard, :discord_settings_admin_role_id, "settings-admin")

    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/",
        current_user: %{id: 1, username: "owner", discord_roles: ["member"]},
        presences: %{}
      )

    assert html =~ "Permissions"
    refute html =~ "Settings"
  end

  test "uses single-row desktop user pills layout when fewer than 6 users are visible" do
    presences =
      for i <- 1..5, into: %{} do
        username = "user#{i}"
        {Integer.to_string(i), %{metas: [%{user: %{username: username, avatar: "#{username}.png"}}]}}
      end

    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/",
        current_user: nil,
        presences: presences
      )

    assert html =~ "flex justify-between h-16"
    assert html =~ "text-sm text-gray-600 dark:text-gray-400 flex items-center gap-2"
    refute html =~ "grid grid-flow-col grid-rows-2"
  end

  test "uses two-row desktop user pills layout when 6 or more users are visible" do
    presences =
      for i <- 1..6, into: %{} do
        username = "user#{i}"
        {Integer.to_string(i), %{metas: [%{user: %{username: username, avatar: "#{username}.png"}}]}}
      end

    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/",
        current_user: nil,
        presences: presences
      )

    assert html =~ "flex justify-between min-h-24 py-2"
    assert html =~ "text-sm text-gray-600 dark:text-gray-400 grid grid-flow-col grid-rows-2"
  end
end
