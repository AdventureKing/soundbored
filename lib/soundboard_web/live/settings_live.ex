defmodule SoundboardWeb.SettingsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  alias Soundboard.Accounts.{ApiTokens, Permissions, RoleCooldowns}
  alias Soundboard.Discord.GuildCache
  alias Soundboard.PublicURL

  @impl true
  def mount(_params, session, socket) do
    current_user = get_user_from_session(session)

    if Permissions.can_manage_settings?(current_user) do
      socket =
        socket
        |> mount_presence(session)
        |> assign(:current_path, "/settings")
        |> assign(:current_user, current_user)
        |> assign(:tokens, [])
        |> assign(:new_token, nil)
        |> assign(:role_cooldown_rows, [])
        |> assign(:role_cooldown_role_ids, [])
        |> assign(:base_url, PublicURL.current())

      {:ok, socket |> load_role_cooldown_rows() |> load_tokens()}
    else
      {:ok,
       socket
       |> put_flash(:error, "You are not allowed to access settings.")
       |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :base_url, PublicURL.from_uri_or_current(uri))}
  end

  @impl true
  def handle_event(
        "create_token",
        %{"label" => label},
        %{assigns: %{current_user: user}} = socket
      ) do
    case ApiTokens.generate_token(user, %{label: String.trim(label)}) do
      {:ok, raw, _token} ->
        {:noreply,
         socket
         |> assign(:new_token, raw)
         |> load_tokens()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create token")}
    end
  end

  @impl true
  def handle_event("revoke_token", %{"id" => id}, %{assigns: %{current_user: user}} = socket) do
    case ApiTokens.revoke_token(user, id) do
      {:ok, _} -> {:noreply, socket |> load_tokens() |> put_flash(:info, "Token revoked")}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, "Not allowed")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Token not found")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to revoke token")}
    end
  end

  @impl true
  def handle_event("save_role_cooldowns", %{"cooldowns" => cooldown_inputs}, socket) do
    case RoleCooldowns.replace_for_roles(
           socket.assigns[:role_cooldown_role_ids] || [],
           cooldown_inputs
         ) do
      :ok ->
        {:noreply,
         socket |> load_role_cooldown_rows() |> put_flash(:info, "Role cooldowns saved")}

      {:error, {:invalid_cooldown, message}} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("save_role_cooldowns", _params, socket) do
    {:noreply, put_flash(socket, :error, "Invalid cooldown submission")}
  end

  defp load_tokens(%{assigns: %{current_user: nil}} = socket), do: socket

  defp load_tokens(%{assigns: %{current_user: user}} = socket) do
    tokens = ApiTokens.list_tokens(user)

    example =
      socket.assigns[:new_token] ||
        case tokens do
          [%{token: tok} | _] when is_binary(tok) -> tok
          _ -> nil
        end

    socket
    |> assign(:tokens, tokens)
    |> assign(:example_token, example)
  end

  defp load_role_cooldown_rows(socket) do
    cooldowns = RoleCooldowns.cooldown_by_role_id()

    cached_rows =
      safe_cached_guilds()
      |> filter_to_target_guild()
      |> Enum.flat_map(fn guild ->
        List.wrap(guild[:roles])
        |> Enum.map(fn role ->
          role_id = role[:id]

          %{
            guild_name: guild[:name] || "Unknown guild",
            role_id: role_id,
            role_name: role[:name] || "Unknown role",
            cooldown_seconds: Map.get(cooldowns, role_id),
            sort_position: role[:position] || 0
          }
        end)
      end)
      |> Enum.filter(&(is_binary(&1.role_id) and &1.role_id != ""))
      |> Enum.sort_by(fn row ->
        {String.downcase(row.guild_name), -row.sort_position, String.downcase(row.role_name)}
      end)
      |> Enum.uniq_by(& &1.role_id)

    cached_role_ids = MapSet.new(Enum.map(cached_rows, & &1.role_id))

    uncached_rows =
      cooldowns
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(cached_role_ids, &1))
      |> Enum.sort()
      |> Enum.map(fn role_id ->
        %{
          guild_name: "Not in cache",
          role_id: role_id,
          role_name: "(unknown role)",
          cooldown_seconds: Map.get(cooldowns, role_id),
          sort_position: -1
        }
      end)

    rows = cached_rows ++ uncached_rows
    role_ids = Enum.map(rows, & &1.role_id)

    socket
    |> assign(:role_cooldown_rows, rows)
    |> assign(:role_cooldown_role_ids, role_ids)
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

  defp normalize_optional_discord_id(value) when is_binary(value),
    do: value |> String.trim() |> empty_to_nil()

  defp normalize_optional_discord_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_discord_id(_), do: nil

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <h1 class="text-2xl font-bold text-gray-800 dark:text-gray-100">Settings</h1>

      <section aria-labelledby="role-cooldowns-heading" class="space-y-3">
        <header class="space-y-1">
          <h2 id="role-cooldowns-heading" class="text-xl font-semibold text-gray-800 dark:text-gray-100">
            Role Cooldowns
          </h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Set playback cooldowns per Discord role. Users with multiple roles get the lowest cooldown.
            Default cooldown is 10 minutes.
          </p>
        </header>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-4">
          <%= if @role_cooldown_rows == [] do %>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              No guild roles are available in cache yet. Keep the bot connected to Discord, then refresh.
            </p>
          <% else %>
            <form phx-submit="save_role_cooldowns" class="space-y-4">
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700 text-sm">
                  <thead class="bg-gray-50 dark:bg-gray-900">
                    <tr>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Guild
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Role
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Role ID
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Cooldown (seconds)
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                    <%= for row <- @role_cooldown_rows do %>
                      <tr>
                        <td class="px-4 py-2 text-gray-600 dark:text-gray-300 whitespace-nowrap">
                          {row.guild_name}
                        </td>
                        <td class="px-4 py-2 text-gray-900 dark:text-gray-100 whitespace-nowrap">
                          {row.role_name}
                        </td>
                        <td class="px-4 py-2 text-gray-500 dark:text-gray-400 whitespace-nowrap font-mono">
                          {row.role_id}
                        </td>
                        <td class="px-4 py-2">
                          <input
                            type="number"
                            min="0"
                            step="1"
                            inputmode="numeric"
                            name={"cooldowns[#{row.role_id}]"}
                            value={row.cooldown_seconds || ""}
                            class="block w-full rounded-md border-gray-300 dark:border-gray-700 shadow-sm dark:bg-gray-900 dark:text-gray-100 focus:border-blue-500 focus:ring-blue-500"
                          />
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>

              <p class="text-xs text-gray-600 dark:text-gray-400">
                Leave blank (or set to 0) to use the default cooldown (10 minutes) for that role.
              </p>

              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-md font-medium hover:bg-blue-700 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
              >
                Save Cooldowns
              </button>
            </form>
          <% end %>
        </div>
      </section>

      <section aria-labelledby="api-tokens-heading" class="space-y-6">
        <header class="space-y-2">
          <h2 id="api-tokens-heading" class="text-xl font-semibold text-gray-800 dark:text-gray-100">
            API Tokens
          </h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Create a personal token to play sounds remotely. Requests authenticated with a token
            are attributed to your account and update your stats.
          </p>
        </header>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-4">
          <form phx-submit="create_token" class="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div class="flex-1">
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">Label</label>
              <input
                name="label"
                type="text"
                placeholder="e.g., CI Bot"
                class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-700 shadow-sm dark:bg-gray-900 dark:text-gray-100 focus:border-blue-500 focus:ring-blue-500"
              />
            </div>
            <button
              type="submit"
              class="w-full sm:w-auto justify-center px-4 py-2 bg-blue-600 text-white rounded-md font-medium hover:bg-blue-700 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900 flex items-center"
            >
              Create
            </button>
          </form>
        </div>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow overflow-hidden">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700 text-sm">
              <thead class="bg-gray-50 dark:bg-gray-900">
                <tr>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Label
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Token
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Created
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Last Used
                  </th>
                  <th class="px-4 py-2"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <%= for token <- @tokens do %>
                  <tr class="text-sm">
                    <td class="px-4 py-2 text-gray-900 dark:text-gray-100 whitespace-nowrap">
                      {token.label || "(no label)"}
                    </td>
                    <td class="px-4 py-2 align-top">
                      <div class="relative">
                        <button
                          id={"copy-token-#{token.id}"}
                          type="button"
                          phx-hook="CopyButton"
                          data-copy-text={token.token}
                          class="absolute right-2 top-1/2 -translate-y-1/2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                        >
                          Copy
                        </button>
                        <pre class="p-2 pr-20 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap"><code class="text-gray-800 dark:text-gray-100 font-mono">{token.token}</code></pre>
                      </div>
                    </td>
                    <td class="px-4 py-2 text-gray-500 dark:text-gray-400 whitespace-nowrap">
                      {format_dt(token.inserted_at)}
                    </td>
                    <td class="px-4 py-2 text-gray-500 dark:text-gray-400 whitespace-nowrap">
                      {format_dt(token.last_used_at) || "—"}
                    </td>
                    <td class="px-4 py-2 text-right align-top">
                      <button
                        phx-click="revoke_token"
                        phx-value-id={token.id}
                        class="px-3 py-1 bg-red-600 text-white rounded hover:bg-red-700 transition-colors focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
                      >
                        Revoke
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-4">
          <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-100">How to call the API</h3>
          <p class="text-sm text-gray-700 dark:text-gray-300">
            Include your token in the Authorization header:
            <code class="px-1 py-0.5 rounded bg-gray-100 dark:bg-gray-800 text-gray-800 dark:text-gray-100 font-mono">
              Authorization: Bearer {@example_token || "<token>"}
            </code>
          </p>
          <div class="space-y-4">
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">List sounds</div>
              <div class="relative">
                <button
                  id="copy-list-sounds"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds</code></pre>
              </div>
            </div>
            <div class="text-xs text-gray-600 dark:text-gray-400">
              Upload endpoint: <code class="font-mono">POST /api/sounds</code>. Required fields:
              <code class="font-mono">name</code>
              plus either <code class="font-mono">file</code>
              (local multipart)
              or <code class="font-mono">url</code>
              (<code class="font-mono">source_type=url</code>). Optional: <code class="font-mono">tags</code>,
              <code class="font-mono">volume</code>
              (0-150), <code class="font-mono">is_join_sound</code>, <code class="font-mono">is_leave_sound</code>.
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">
                Upload local file (multipart/form-data)
              </div>
              <div class="relative">
                <button
                  id="copy-upload-local"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" -F \"source_type=local\" -F \"name=<NAME>\" -F \"file=@/path/to/sound.mp3\" -F \"tags[]=meme\" -F \"tags[]=alert\" -F \"volume=90\" -F \"is_join_sound=true\" #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto min-h-[120px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST \
    -H "Authorization: Bearer {(@example_token || "<TOKEN>")}" \
    -F "source_type=local" \
    -F "name=&lt;NAME&gt;" \
    -F "file=@/path/to/sound.mp3" \
    -F "tags[]=meme" \
    -F "tags[]=alert" \
    -F "volume=90" \
    -F "is_join_sound=true" \
    {@base_url}/api/sounds</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">
                Upload from URL (JSON)
              </div>
              <div class="relative">
                <button
                  id="copy-upload-url"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" -H \"Content-Type: application/json\" -d '{\"source_type\":\"url\",\"name\":\"wow\",\"url\":\"https://example.com/wow.mp3\",\"tags\":[\"meme\",\"reaction\"],\"volume\":90,\"is_leave_sound\":true}' #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto min-h-[110px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST \
    -H "Authorization: Bearer {(@example_token || "<TOKEN>")}" \
    -H "Content-Type: application/json" \
    -d '&#123;"source_type":"url","name":"wow","url":"https://example.com/wow.mp3","tags":["meme","reaction"],"volume":90,"is_leave_sound":true&#125;' \
    {@base_url}/api/sounds</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">
                Play a sound by ID
              </div>
              <div class="relative">
                <button
                  id="copy-play-sound"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds/<SOUND_ID>/play"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds/&lt;SOUND_ID&gt;/play</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">Stop all sounds</div>
              <div class="relative">
                <button
                  id="copy-stop-sounds"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds/stop"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds/stop</code></pre>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp format_dt(nil), do: nil
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
