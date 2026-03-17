defmodule SoundboardWeb.Components.Layouts.NavbarTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias SoundboardWeb.Components.Layouts.Navbar

  setup do
    original_admin_user_ids =
      Application.get_env(:soundboard, :discord_settings_admin_user_ids, [])

    on_exit(fn ->
      Application.put_env(:soundboard, :discord_settings_admin_user_ids, original_admin_user_ids)
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

    assert html =~ "BeeBot"
    assert html =~ "buzz-mode-toggle-desktop"
    assert html =~ "buzz-mode-toggle-mobile"
    assert html =~ "Sounds"
    assert html =~ "Stats"
    refute html =~ "Permissions"
    refute html =~ "Settings"
    refute html =~ "Re-auth"
  end

  test "renders permissions/settings links and deduplicated presences for admin users" do
    Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["owner-1"])

    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/settings",
        current_user: %{
          id: 1,
          discord_id: "owner-1",
          username: "owner",
          discord_roles: ["member"]
        },
        presences: %{
          "1" => %{metas: [%{user: %{username: "alice", avatar: "alice.png"}}]},
          "2" => %{metas: [%{user: %{username: "alice", avatar: "alice.png"}}]},
          "3" => %{metas: [%{user: %{username: "bob", avatar: "bob.png"}}]}
        }
      )

    assert html =~ "Permissions"
    assert html =~ "Settings"
    assert html =~ "Re-auth"
    assert html =~ "/auth/discord"
    assert html =~ "desktop-user-alice"
    assert html =~ "desktop-user-bob"

    # Duplicated presence entries for the same user should render once per menu section.
    assert length(Regex.scan(~r/user-alice/, html)) == 2
  end

  test "toggle-mobile-menu flips show_mobile_menu assign" do
    {:ok, socket} = Navbar.mount(%Phoenix.LiveView.Socket{})

    {:noreply, socket} = Navbar.handle_event("toggle-mobile-menu", %{}, socket)
    assert socket.assigns.show_mobile_menu

    {:noreply, socket} = Navbar.handle_event("toggle-mobile-menu", %{}, socket)
    refute socket.assigns.show_mobile_menu
  end

  test "toggle-desktop-nav flips desktop_nav_collapsed assign" do
    {:ok, socket} = Navbar.mount(%Phoenix.LiveView.Socket{})

    {:noreply, socket} = Navbar.handle_event("toggle-desktop-nav", %{}, socket)
    assert socket.assigns.desktop_nav_collapsed

    {:noreply, socket} = Navbar.handle_event("toggle-desktop-nav", %{}, socket)
    refute socket.assigns.desktop_nav_collapsed
  end

  test "hides settings link when admin user IDs are configured and user is not included" do
    Application.put_env(:soundboard, :discord_settings_admin_user_ids, ["owner-1"])

    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/",
        current_user: %{
          id: 1,
          discord_id: "owner-2",
          username: "owner",
          discord_roles: ["member"]
        },
        presences: %{}
      )

    assert html =~ "Permissions"
    assert html =~ "Re-auth"
    refute html =~ "Settings"
  end

  test "renders desktop expand control when nav is collapsed" do
    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/",
        current_user: nil,
        presences: %{},
        desktop_nav_collapsed: true
      )

    assert html =~ "expand-desktop-nav"
    assert html =~ "title=\"Sounds\""
    assert html =~ "title=\"Stats\""
    refute html =~ "collapse-desktop-nav"
  end
end
