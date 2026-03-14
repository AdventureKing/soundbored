defmodule SoundboardWeb.PermissionsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive

  alias Soundboard.Accounts.Permissions

  @impl true
  def mount(_params, session, socket) do
    current_user = get_user_from_session(session)

    {:ok,
     socket
     |> mount_presence(session)
     |> assign(:current_path, "/permissions")
     |> assign(:current_user, current_user)
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
            Play access is decided from your Discord role IDs.
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
              <span class="font-semibold">Your role IDs:</span>
              {format_ids(@play_permission.user_ids)}
            </div>
            <div>
              <span class="font-semibold">Allowed player role IDs:</span>
              {format_ids(@play_permission.required_ids)}
            </div>
          </div>
        </div>
      </section>

      <section class="space-y-3">
        <header class="space-y-1">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100">Clip Upload</h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Upload access is decided from your Discord role IDs.
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
              <span class="font-semibold">Your role IDs:</span>
              {format_ids(@upload_permission.user_ids)}
            </div>
            <div>
              <span class="font-semibold">Allowed uploader role IDs:</span>
              {format_ids(@upload_permission.required_ids)}
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
    "At least one of your Discord role IDs matches the configured uploader roles."
  end

  defp permission_message(%{reason: :missing_required_role}) do
    "None of your Discord role IDs match the configured uploader roles."
  end

  defp permission_message(%{reason: :no_user}) do
    "You must be signed in to upload clips."
  end

  defp play_permission_message(%{reason: :allowed_by_default}) do
    "No player roles are configured, so all authenticated users may play clips."
  end

  defp play_permission_message(%{reason: :role_match}) do
    "At least one of your Discord role IDs matches the configured player roles."
  end

  defp play_permission_message(%{reason: :missing_required_role}) do
    "None of your Discord role IDs match the configured player roles."
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

  defp format_ids([]), do: "none"
  defp format_ids(ids), do: Enum.join(ids, ", ")
end
