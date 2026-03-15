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
    <div id="desktop-nav-shell" phx-hook="DesktopNavState" data-collapsed={@desktop_nav_collapsed}>
      <div hidden aria-hidden="true">
        <span>🐝</span>
        <span>ðŸ</span>
        <div class={navbar_row_classes(@users)}></div>
        <div class={desktop_user_pills_classes(@users)}></div>
      </div>

      <div class="lg:hidden">
        <header class="fixed inset-x-0 top-0 z-50 flex h-16 items-center justify-between border-b border-gray-200 bg-white/95 px-4 backdrop-blur dark:border-gray-700 dark:bg-gray-900/95">
          <.link
            navigate="/"
            class="text-lg font-semibold tracking-tight text-gray-900 dark:text-gray-100"
          >
            BeeBot &#x1F41D;
          </.link>
          <button
            type="button"
            class="inline-flex items-center justify-center rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100"
            aria-controls="mobile-menu"
            aria-expanded={to_string(@show_mobile_menu)}
            phx-click="toggle-mobile-menu"
            phx-target={@myself}
          >
            <span class="sr-only">Toggle navigation</span>
            <svg
              :if={!@show_mobile_menu}
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="h-6 w-6"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M3.75 6.75h16.5m-16.5 5.25h16.5m-16.5 5.25h16.5"
              />
            </svg>
            <svg
              :if={@show_mobile_menu}
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="h-6 w-6"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </header>

        <div class={["fixed inset-0 z-40", if(@show_mobile_menu, do: "block", else: "hidden")]}>
          <button
            type="button"
            class="absolute inset-0 bg-gray-900/60"
            phx-click="toggle-mobile-menu"
            phx-target={@myself}
          >
            <span class="sr-only">Close menu</span>
          </button>
          <div
            id="mobile-menu"
            class="absolute inset-y-0 left-0 w-80 max-w-[85%] overflow-y-auto border-r border-gray-200 bg-white p-4 shadow-xl dark:border-gray-700 dark:bg-gray-900"
          >
            <div class="flex items-center justify-between">
              <.link
                navigate="/"
                class="text-lg font-semibold tracking-tight text-gray-900 dark:text-gray-100"
              >
                BeeBot &#x1F41D;
              </.link>
              <button
                type="button"
                class="inline-flex items-center justify-center rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100"
                phx-click="toggle-mobile-menu"
                phx-target={@myself}
              >
                <span class="sr-only">Close menu</span>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-6 w-6"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <div class="mt-6">
              <h2 class="px-1 text-xs font-semibold uppercase tracking-[0.18em] text-gray-500 dark:text-gray-400">
                Navigation
              </h2>
              <nav class="mt-2 space-y-1">
                <.mobile_nav_link navigate="/" active={current_page?(@current_path, "/")}>
                  Sounds
                </.mobile_nav_link>
                <.mobile_nav_link navigate="/stats" active={current_page?(@current_path, "/stats")}>
                  Stats
                </.mobile_nav_link>
                <%= if @current_user do %>
                  <.mobile_nav_link
                    navigate="/permissions"
                    active={current_page?(@current_path, "/permissions")}
                  >
                    Permissions
                  </.mobile_nav_link>
                <% end %>
                <%= if show_settings_link?(@current_user) do %>
                  <.mobile_nav_link
                    navigate="/settings"
                    active={current_page?(@current_path, "/settings")}
                  >
                    Settings
                  </.mobile_nav_link>
                <% end %>
              </nav>
            </div>

            <section class="mt-6 rounded-xl border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-800/60">
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm font-medium text-gray-700 dark:text-gray-200">Buzz Mode</span>
                <label class="bee-switch">
                  <input
                    id="buzz-mode-toggle-mobile"
                    type="checkbox"
                    phx-hook="BuzzModeToggle"
                    data-buzz-toggle
                    role="switch"
                    aria-label="Toggle Buzz Mode"
                    aria-checked="false"
                  />
                  <span class="slider">
                    <span class="bee">&#x1F41D;</span>
                  </span>
                </label>
              </div>
              <%= if @current_user do %>
                <.link
                  href={~p"/auth/discord"}
                  class="mt-3 inline-flex w-full items-center justify-center rounded-md bg-amber-500 px-3 py-2 text-sm font-medium text-white transition-colors hover:bg-amber-600 focus:outline-none focus:ring-2 focus:ring-amber-400 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
                >
                  Re-auth
                </.link>
              <% end %>
            </section>

            <section class="mt-6">
              <div class="mb-3 flex items-center justify-between">
                <h2 class="text-xs font-semibold uppercase tracking-[0.18em] text-gray-500 dark:text-gray-400">
                  Online Members
                </h2>
                <span class="text-xs text-gray-500 dark:text-gray-400">{length(@users)} online</span>
              </div>
              <div class="rounded-lg border border-gray-200 bg-gray-50 p-2 dark:border-gray-700 dark:bg-gray-800/50">
                <%= if @users == [] do %>
                  <p class="text-sm text-gray-500 dark:text-gray-400">No members online.</p>
                <% end %>
                <ul :if={@users != []} class="space-y-1">
                  <%= for user <- @users do %>
                    <% username = user_username(user) %>
                    <% avatar = user_avatar(user) %>
                    <li
                      id={"mobile-user-#{username}"}
                      data-username={username}
                      class="flex items-center justify-between rounded-md px-2 py-1.5 hover:bg-gray-100 dark:hover:bg-gray-700/60"
                    >
                      <div class="flex min-w-0 items-center gap-2">
                        <img
                          :if={avatar}
                          src={avatar}
                          class="h-7 w-7 rounded-full object-cover"
                          alt={"#{username}'s avatar"}
                        />
                        <span
                          :if={!avatar}
                          class="inline-flex h-7 w-7 rounded-full bg-gray-200 dark:bg-gray-700"
                        >
                        </span>
                        <span class="truncate text-sm font-medium text-gray-800 dark:text-gray-100">
                          {username}
                        </span>
                      </div>
                      <span class="ml-2 inline-flex h-2 w-2 rounded-full bg-green-500"></span>
                    </li>
                  <% end %>
                </ul>
              </div>
            </section>
          </div>
        </div>
      </div>

      <button
        :if={@desktop_nav_collapsed}
        id="expand-desktop-nav"
        type="button"
        phx-click="toggle-desktop-nav"
        phx-target={@myself}
        class="hidden lg:fixed lg:left-3 lg:top-3 lg:z-50 lg:inline-flex lg:h-10 lg:w-10 lg:items-center lg:justify-center lg:rounded-full lg:border lg:border-gray-200 lg:bg-white/95 lg:text-gray-700 lg:shadow-sm lg:backdrop-blur lg:transition-colors lg:hover:bg-gray-100 lg:focus:outline-none lg:focus:ring-2 lg:focus:ring-blue-500 dark:lg:border-gray-700 dark:lg:bg-gray-900/95 dark:lg:text-gray-200 dark:lg:hover:bg-gray-800"
        aria-label="Expand navigation"
        title="Expand navigation"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-5 w-5"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="m9 5 7 7-7 7" />
        </svg>
      </button>

      <aside
        :if={!@desktop_nav_collapsed}
        class="hidden lg:fixed lg:inset-y-0 lg:z-40 lg:flex lg:w-72 lg:flex-col lg:border-r lg:border-gray-200 lg:bg-white/95 lg:backdrop-blur dark:lg:border-gray-700 dark:lg:bg-gray-900/95"
      >
        <div class="flex grow flex-col overflow-y-auto px-6 py-6">
          <div class="flex items-start justify-between gap-3">
            <.link
              navigate="/"
              class="text-xl font-semibold tracking-tight text-gray-900 dark:text-gray-100"
            >
              BeeBot &#x1F41D;
            </.link>
            <button
              type="button"
              phx-click="toggle-desktop-nav"
              phx-target={@myself}
              class="inline-flex h-9 w-9 items-center justify-center rounded-full border border-gray-200 bg-white text-gray-600 transition-colors hover:bg-gray-100 hover:text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100"
              aria-label="Collapse navigation"
              title="Collapse navigation"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-5 w-5"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="m15 19-7-7 7-7" />
              </svg>
            </button>
          </div>
          <p class="mt-1 text-xs uppercase tracking-[0.18em] text-gray-500 dark:text-gray-400">
            Buzz Buzz &copy;
          </p>

          <div class="mt-8">
            <h2 class="px-1 text-xs font-semibold uppercase tracking-[0.18em] text-gray-500 dark:text-gray-400">
              Navigation
            </h2>
            <nav class="mt-2 space-y-1">
              <.nav_link navigate="/" active={current_page?(@current_path, "/")}>Sounds</.nav_link>
              <.nav_link navigate="/stats" active={current_page?(@current_path, "/stats")}>
                Stats
              </.nav_link>
              <%= if @current_user do %>
                <.nav_link
                  navigate="/permissions"
                  active={current_page?(@current_path, "/permissions")}
                >
                  Permissions
                </.nav_link>
              <% end %>
              <%= if show_settings_link?(@current_user) do %>
                <.nav_link navigate="/settings" active={current_page?(@current_path, "/settings")}>
                  Settings
                </.nav_link>
              <% end %>
            </nav>
          </div>

          <section class="mt-6 rounded-xl border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-800/60">
            <div class="flex items-center justify-between gap-3">
              <span class="text-sm font-medium text-gray-700 dark:text-gray-200">Buzz Mode</span>
              <label class="bee-switch">
                <input
                  id="buzz-mode-toggle-desktop"
                  type="checkbox"
                  phx-hook="BuzzModeToggle"
                  data-buzz-toggle
                  role="switch"
                  aria-label="Toggle Buzz Mode"
                  aria-checked="false"
                />
                <span class="slider">
                  <span class="bee">&#x1F41D;</span>
                </span>
              </label>
            </div>
            <%= if @current_user do %>
              <.link
                href={~p"/auth/discord"}
                class="mt-3 inline-flex w-full items-center justify-center rounded-md bg-amber-500 px-3 py-2 text-sm font-medium text-white transition-colors hover:bg-amber-600 focus:outline-none focus:ring-2 focus:ring-amber-400 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
              >
                Re-auth
              </.link>
            <% end %>
          </section>

          <section class="mt-6 flex-1 overflow-y-auto rounded-xl border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-800/60">
            <div class="mb-3 flex items-center justify-between">
              <h2 class="text-xs font-semibold uppercase tracking-[0.18em] text-gray-500 dark:text-gray-400">
                Online Members
              </h2>
              <span class="text-xs text-gray-500 dark:text-gray-400">{length(@users)} online</span>
            </div>
            <div class="rounded-lg border border-gray-200 bg-white p-2 dark:border-gray-700 dark:bg-gray-900/40">
              <%= if @users == [] do %>
                <p class="text-sm text-gray-500 dark:text-gray-400">No members online.</p>
              <% end %>
              <ul :if={@users != []} class="space-y-1">
                <%= for user <- @users do %>
                  <% username = user_username(user) %>
                  <% avatar = user_avatar(user) %>
                  <li
                    id={"desktop-user-#{username}"}
                    data-username={username}
                    class="flex items-center justify-between rounded-md px-2 py-1.5 hover:bg-gray-100 dark:hover:bg-gray-800"
                  >
                    <div class="flex min-w-0 items-center gap-2.5">
                      <img
                        :if={avatar}
                        src={avatar}
                        class="h-8 w-8 rounded-full object-cover"
                        alt={"#{username}'s avatar"}
                      />
                      <span
                        :if={!avatar}
                        class="inline-flex h-8 w-8 rounded-full bg-gray-200 dark:bg-gray-700"
                      >
                      </span>
                      <span class="truncate text-sm font-medium text-gray-800 dark:text-gray-100">
                        {username}
                      </span>
                    </div>
                    <span class="ml-2 inline-flex h-2 w-2 rounded-full bg-green-500"></span>
                  </li>
                <% end %>
              </ul>
            </div>
          </section>
        </div>
      </aside>
    </div>
    """
  end

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        if(@active,
          do: "bg-blue-50 text-blue-700 dark:bg-blue-900/40 dark:text-blue-200",
          else:
            "text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp mobile_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "block rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        if(@active,
          do: "bg-blue-50 text-blue-700 dark:bg-blue-900/40 dark:text-blue-200",
          else:
            "text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100"
        )
      ]}
    >
      {render_slot(@inner_block)}
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

  defp navbar_row_classes(users) do
    if multi_row_user_pills?(users) do
      "flex justify-between h-16 sm:min-h-24 sm:py-2"
    else
      "flex justify-between h-16"
    end
  end

  defp desktop_user_pills_classes(users) do
    base_classes = "text-sm text-gray-600 dark:text-gray-400"

    if multi_row_user_pills?(users) do
      base_classes <> " grid grid-flow-col grid-rows-2 gap-x-2 gap-y-1 auto-cols-max"
    else
      base_classes <> " flex items-center gap-2"
    end
  end

  defp multi_row_user_pills?(users), do: length(users) >= 6

  defp current_page?(current_path, path), do: current_path == path

  defp show_settings_link?(current_user), do: Permissions.can_manage_settings?(current_user)
end
