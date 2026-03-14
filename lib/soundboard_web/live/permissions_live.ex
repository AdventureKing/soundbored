defmodule SoundboardWeb.PermissionsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive

  alias Soundboard.Accounts.Permissions
  alias Soundboard.Discord.GuildCache

  @impl true
  def mount(_params, session, socket) do
    current_user = get_user_from_session(session)

    {:ok,
     socket
     |> mount_presence(session)
     |> assign(:current_path, "/permissions")
     |> assign(:current_user, current_user)
     |> assign(:role_name_map, role_name_map())
     |> assign(:play_permission, Permissions.permission_decision(current_user, :play_clips))
     |> assign(:upload_permission, Permissions.permission_decision(current_user, :upload_clips))
     |> assign(
       :settings_permission,
       Permissions.permission_decision(current_user, :manage_settings)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <h1 class="text-2xl font-bold text-gray-800 dark:text-gray-100">Permissions</h1>

      <section class="space-y-3">
        <header class="space-y-1">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100">Clip Playback</h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Play access is decided from your Discord roles.
          </p>
        </header>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-3">
          <p class="text-sm">
            <span class="font-semibold text-gray-700 dark:text-gray-200">Status:</span>
            <span class={status_class(@play_permission.allowed?)}>
              {if @play_permission.allowed?, do: "Allowed", else: "Not allowed"}
            </span>
          </p>

          <p class="text-xs text-gray-600 dark:text-gray-400">
            {play_permission_message(@play_permission)}
          </p>

          <div class="text-xs text-gray-700 dark:text-gray-300">
            <div>
              <span class="font-semibold">Your roles:</span>
              {format_role_names(@play_permission.user_ids, @role_name_map)}
            </div>
            <div>
              <span class="font-semibold">Allowed player roles:</span>
              {format_role_names(@play_permission.required_ids, @role_name_map)}
            </div>
          </div>
        </div>
      </section>

      <section class="space-y-3">
        <header class="space-y-1">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100">Clip Upload</h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Upload access is decided from your Discord roles.
          </p>
        </header>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-3">
          <p class="text-sm">
            <span class="font-semibold text-gray-700 dark:text-gray-200">Status:</span>
            <span class={status_class(@upload_permission.allowed?)}>
              {if @upload_permission.allowed?, do: "Allowed", else: "Not allowed"}
            </span>
          </p>

          <p class="text-xs text-gray-600 dark:text-gray-400">
            {permission_message(@upload_permission)}
          </p>

          <div class="text-xs text-gray-700 dark:text-gray-300">
            <div>
              <span class="font-semibold">Your roles:</span>
              {format_role_names(@upload_permission.user_ids, @role_name_map)}
            </div>
            <div>
              <span class="font-semibold">Allowed uploader roles:</span>
              {format_role_names(@upload_permission.required_ids, @role_name_map)}
            </div>
          </div>
        </div>
      </section>

      <section :if={@settings_permission.allowed?} class="space-y-3">
        <header class="space-y-1">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100">Settings Access</h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Only users with an allowed Discord user ID can open Settings.
          </p>
        </header>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-3">
          <p class="text-sm">
            <span class="font-semibold text-gray-700 dark:text-gray-200">Status:</span>
            <span class={status_class(@settings_permission.allowed?)}>
              {if @settings_permission.allowed?, do: "Allowed", else: "Not allowed"}
            </span>
          </p>

          <p class="text-xs text-gray-600 dark:text-gray-400">
            {settings_permission_message(@settings_permission)}
          </p>

          <div class="text-xs text-gray-700 dark:text-gray-300">
            <div>
              <span class="font-semibold">Your Discord user ID:</span>
              {format_ids(@settings_permission.user_ids)}
            </div>
            <div>
              <span class="font-semibold">Allowed settings admin user IDs:</span>
              {format_ids(@settings_permission.required_ids)}
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp permission_message(%{reason: :allowed_by_default}) do
    "No uploader roles are configured, so all authenticated users may upload clips."
  end

  defp permission_message(%{reason: :role_match}) do
    "At least one of your Discord roles matches the configured uploader roles."
  end

  defp permission_message(%{reason: :missing_required_role}) do
    "None of your Discord roles match the configured uploader roles."
  end

  defp permission_message(%{reason: :no_user}) do
    "You must be signed in to upload clips."
  end

  defp play_permission_message(%{reason: :allowed_by_default}) do
    "No player roles are configured, so all authenticated users may play clips."
  end

  defp play_permission_message(%{reason: :role_match}) do
    "At least one of your Discord roles matches the configured player roles."
  end

  defp play_permission_message(%{reason: :missing_required_role}) do
    "None of your Discord roles match the configured player roles."
  end

  defp play_permission_message(%{reason: :no_user}) do
    "You must be signed in to play clips."
  end

  defp settings_permission_message(%{reason: :role_match}) do
    "Your Discord user ID is in the configured settings admin user ID list."
  end

  defp settings_permission_message(%{reason: :missing_required_role, required_ids: []}) do
    "No settings admin user IDs are configured."
  end

  defp settings_permission_message(%{reason: :missing_required_role}) do
    "Your Discord user ID is not in the configured settings admin user ID list."
  end

  defp settings_permission_message(%{reason: :no_user}) do
    "You must be signed in to access settings."
  end

  defp status_class(true), do: "text-green-700 dark:text-green-400 font-semibold"
  defp status_class(false), do: "text-red-700 dark:text-red-400 font-semibold"

  defp format_role_names([], _role_name_map), do: "none"

  defp format_role_names(role_ids, role_name_map) when is_map(role_name_map) do
    role_ids
    |> Enum.map(&Map.get(role_name_map, &1, "(unknown role)"))
    |> Enum.join(", ")
  end

  defp format_role_names(role_ids, _role_name_map), do: Enum.join(role_ids, ", ")

  defp format_ids([]), do: "none"
  defp format_ids(ids), do: Enum.join(ids, ", ")

  defp role_name_map do
    safe_cached_guilds()
    |> filter_to_target_guild()
    |> Enum.flat_map(&List.wrap(&1[:roles]))
    |> Enum.reduce(%{}, fn role, acc ->
      role_id = role[:id]
      role_name = role[:name]

      if is_binary(role_id) and role_id != "" and is_binary(role_name) and role_name != "" do
        Map.put(acc, role_id, role_name)
      else
        acc
      end
    end)
  end

  defp safe_cached_guilds do
    GuildCache.all()
  rescue
    _ -> []
  end

  defp filter_to_target_guild(guilds) do
    case configured_role_guild_id() do
      nil ->
        guilds

      guild_id ->
        matched = Enum.filter(guilds, &(to_string(&1.id) == guild_id))
        if matched == [], do: guilds, else: matched
    end
  end

  defp configured_role_guild_id do
    :soundboard
    |> Application.get_env(:discord_role_guild_id)
    |> normalize_optional_discord_id()
    |> case do
      nil ->
        :soundboard
        |> Application.get_env(:required_discord_guild_id)
        |> normalize_optional_discord_id()

      guild_id ->
        guild_id
    end
  end

  defp normalize_optional_discord_id(nil), do: nil

  defp normalize_optional_discord_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> empty_to_nil()
  end

  defp normalize_optional_discord_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_discord_id(_), do: nil

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
