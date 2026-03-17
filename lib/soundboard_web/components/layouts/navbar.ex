defmodule SoundboardWeb.Components.Layouts.Navbar do
  @moduledoc """
  The navbar component.
  """
  use Phoenix.LiveComponent
  use SoundboardWeb, :html
  alias Soundboard.Accounts.Permissions

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(:show_mobile_menu, false) |> assign(:desktop_nav_collapsed, false)}
  end

  @impl true
  def handle_event("toggle-mobile-menu", _, socket) do
    {:noreply, assign(socket, :show_mobile_menu, !socket.assigns.show_mobile_menu)}
  end

  @impl true
  def handle_event("toggle-desktop-nav", _, socket) do
    {:noreply, assign(socket, :desktop_nav_collapsed, !socket.assigns.desktop_nav_collapsed)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :users, visible_users(assigns[:presences]))

    ~H"""
    <div
      id="desktop-nav-shell"
      phx-hook="DesktopNavState"
      data-collapsed={to_string(@desktop_nav_collapsed)}
      class="bb-nav-shell"
    >
      <header class="bb-mobile-top lg:hidden">
        <.link navigate="/" class="bb-mobile-brand">BeeBot &#x1F41D;</.link>
        <button
          type="button"
          class="bb-mobile-menu-btn"
          aria-controls="mobile-menu"
          aria-expanded={to_string(@show_mobile_menu)}
          phx-click="toggle-mobile-menu"
          phx-target={@myself}
        >
          <span class="sr-only">Toggle navigation</span>
          <.icon :if={!@show_mobile_menu} name="hero-bars-3" class="h-5 w-5" />
          <.icon :if={@show_mobile_menu} name="hero-x-mark" class="h-5 w-5" />
        </button>
      </header>

      <div class={["bb-mobile-overlay lg:hidden", if(@show_mobile_menu, do: "open", else: "")]}>
        <button
          type="button"
          class="bb-mobile-backdrop"
          phx-click="toggle-mobile-menu"
          phx-target={@myself}
        >
          <span class="sr-only">Close menu</span>
        </button>

        <aside id="mobile-menu" class="bb-mobile-drawer">
          <.sidebar_content
            users={@users}
            current_path={@current_path}
            current_user={@current_user}
            collapsed={false}
            mobile={true}
            preview_mode={@preview_mode}
            myself={@myself}
            cooldown_end_ms={assigns[:cooldown_end_ms]}
            cooldown_remaining_ms={assigns[:cooldown_remaining_ms]}
          />
        </aside>
      </div>

      <aside class={[
        "bb-desktop-shell hidden lg:flex",
        if(@desktop_nav_collapsed, do: "collapsed", else: "")
      ]}>
        <.sidebar_content
          users={@users}
          current_path={@current_path}
          current_user={@current_user}
          collapsed={@desktop_nav_collapsed}
          mobile={false}
          preview_mode={@preview_mode}
          myself={@myself}
          cooldown_end_ms={assigns[:cooldown_end_ms]}
          cooldown_remaining_ms={assigns[:cooldown_remaining_ms]}
        />
      </aside>
    </div>
    """
  end

  attr :users, :list, default: []
  attr :current_path, :string, default: "/"
  attr :current_user, :any, default: nil
  attr :collapsed, :boolean, default: false
  attr :mobile, :boolean, default: false
  attr :preview_mode, :boolean, default: false
  attr :myself, :any, default: nil
  attr :cooldown_end_ms, :any, default: nil
  attr :cooldown_remaining_ms, :any, default: nil

  defp sidebar_content(assigns) do
    assigns = assign(assigns, :show_settings, show_settings_link?(assigns.current_user))

    ~H"""
    <div class={["bb-sidebar", if(@collapsed, do: "collapsed", else: "")]}>
      <div class="bb-top-row">
        <.link navigate="/" class="bb-brand" aria-label="BeeBot home" title="BeeBot home">
          <span class="bb-brand-icon">&#x1F41D;</span>
          <span class="bb-brand-text">
            <span class="bb-brand-name">BeeBot</span>
            <span class="bb-brand-sub">BUZZ BUZZ</span>
          </span>
        </.link>

        <button
          :if={!@mobile}
          id={if @collapsed, do: "expand-desktop-nav", else: "collapse-desktop-nav"}
          type="button"
          phx-click="toggle-desktop-nav"
          phx-target={@myself}
          class="bb-toggle-btn"
          aria-label={if @collapsed, do: "Expand navigation", else: "Collapse navigation"}
          title={if @collapsed, do: "Expand sidebar", else: "Collapse sidebar"}
        >
          <.icon :if={!@collapsed} name="hero-chevron-left" class="h-4 w-4" />
          <.icon :if={@collapsed} name="hero-chevron-right" class="h-4 w-4" />
        </button>

        <button
          :if={@mobile}
          type="button"
          phx-click="toggle-mobile-menu"
          phx-target={@myself}
          class="bb-toggle-btn"
          aria-label="Close navigation"
          title="Close sidebar"
        >
          <.icon name="hero-x-mark" class="h-4 w-4" />
        </button>
      </div>

      <nav class="bb-nav-list">
        <.beebot_nav_link
          navigate={nav_path(@preview_mode, :sounds)}
          active={current_page?(@current_path, nav_path(@preview_mode, :sounds))}
          icon="hero-musical-note"
          label="Sounds"
        />
        <.beebot_nav_link
          navigate={nav_path(@preview_mode, :stats)}
          active={current_page?(@current_path, nav_path(@preview_mode, :stats))}
          icon="hero-chart-bar-square"
          label="Stats"
        />
        <.beebot_nav_link
          :if={@current_user || @preview_mode}
          navigate={nav_path(@preview_mode, :permissions)}
          active={current_page?(@current_path, nav_path(@preview_mode, :permissions))}
          icon="hero-shield-check"
          label="Permissions"
        />
        <.beebot_nav_link
          :if={@show_settings || @preview_mode}
          navigate={nav_path(@preview_mode, :settings)}
          active={current_page?(@current_path, nav_path(@preview_mode, :settings))}
          icon="hero-cog-6-tooth"
          label="Settings"
        />
      </nav>

      <div
        id={if @mobile, do: "sidebar-cooldown-mobile", else: "sidebar-cooldown-desktop"}
        phx-hook="CooldownTimer"
        data-cooldown-end-ms={@cooldown_end_ms || ""}
        data-cooldown-remaining-ms={@cooldown_remaining_ms || ""}
        class="bb-cooldown"
      >
        <span class="bb-cooldown-dot"></span>
        <span class="bb-cooldown-text">Cooldown <span data-role="cooldown-value">Ready</span></span>
      </div>

      <div class="bb-divider">
        <span class="line"></span>
        <span class="label">Online &#183; {length(@users)}</span>
        <span class="line"></span>
      </div>

      <div class="bb-members-list">
        <%= if @users == [] do %>
          <div class="bb-empty-members">No members online.</div>
        <% end %>

        <%= for user <- @users do %>
          <% username = user_username(user) %>
          <% avatar = user_avatar(user) %>
          <div id={member_id(@mobile, username)} data-username={username} class="bb-member">
            <div class="bb-avatar-wrap">
              <img
                :if={avatar}
                src={avatar}
                class="bb-avatar object-cover"
                alt={"#{username}'s avatar"}
              />
              <span :if={!avatar} class="bb-avatar bb-avatar-fallback">{user_initial(username)}</span>
              <span class="bb-online-dot"></span>
            </div>
            <span class="bb-member-name">{username}</span>
          </div>
        <% end %>
      </div>

      <div class="bb-footer">
        <div :if={!@collapsed} class="bb-buzz-row">
          <span class="bb-buzz-label">Buzz Mode</span>
          <label class="bee-switch" aria-label="Toggle Buzz Mode">
            <input
              id={if @mobile, do: "buzz-mode-toggle-mobile", else: "buzz-mode-toggle-desktop"}
              type="checkbox"
              phx-hook="BuzzModeToggle"
              data-buzz-toggle
              role="switch"
              aria-label="Buzz Mode"
            />
            <span class="slider">
              <span class="bee">&#x1F41D;</span>
            </span>
          </label>
        </div>

        <.link :if={@current_user} href={~p"/auth/discord"} class="bb-reauth-link">
          Re-auth
        </.link>
      </div>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp beebot_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      title={@label}
      aria-label={@label}
      class={["bb-nav-item", if(@active, do: "active", else: "")]}
    >
      <span class="bb-nav-icon"><.icon name={@icon} class="h-4 w-4" /></span>
      <span class="bb-nav-item-label">{@label}</span>
    </.link>
    """
  end

  defp visible_users(presences) when is_map(presences) do
    presences
    |> Enum.flat_map(fn {_id, presence} ->
      presence
      |> Map.get(:metas, [])
      |> List.wrap()
      |> Enum.map(&Map.get(&1, :user, %{}))
    end)
    |> Enum.filter(&is_binary(user_username(&1)))
    |> Enum.uniq_by(&user_username/1)
  end

  defp visible_users(_), do: []

  defp user_username(%{} = user), do: Map.get(user, :username) || Map.get(user, "username")
  defp user_username(_), do: nil

  defp user_avatar(%{} = user), do: Map.get(user, :avatar) || Map.get(user, "avatar")
  defp user_avatar(_), do: nil

  defp current_page?(current_path, path), do: current_path == path

  defp show_settings_link?(current_user), do: Permissions.can_manage_settings?(current_user)

  defp nav_path(true, :sounds), do: "/preview/soundboard"
  defp nav_path(true, :stats), do: "/preview/stats"
  defp nav_path(true, :permissions), do: "/preview/permissions"
  defp nav_path(true, :settings), do: "/preview/settings"
  defp nav_path(false, :sounds), do: "/"
  defp nav_path(false, :stats), do: "/stats"
  defp nav_path(false, :permissions), do: "/permissions"
  defp nav_path(false, :settings), do: "/settings"

  defp member_id(true, username), do: "mobile-user-#{slug(username)}"
  defp member_id(false, username), do: "desktop-user-#{slug(username)}"

  defp slug(value) when is_binary(value) do
    Regex.replace(~r/[^a-zA-Z0-9_-]/, value, "-")
  end

  defp slug(_), do: "user"

  defp user_initial(username) when is_binary(username) do
    username
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      char -> String.upcase(char)
    end
  end

  defp user_initial(_), do: "?"
end
