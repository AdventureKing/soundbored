defmodule SoundboardWeb.SettingsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  alias Soundboard.Accounts.{ApiTokens, Permissions, RoleCooldowns}
  alias Soundboard.Discord.GuildCache
  alias Soundboard.Sounds.Tags
  alias Soundboard.PublicURL
  @role_cooldown_sort_fields [:guild_name, :role_name, :role_id, :cooldown_seconds]

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
        |> assign(:role_cooldown_filter, "")
        |> assign(:role_cooldown_sort_by, :role_name)
        |> assign(:role_cooldown_sort_dir, :asc)
        |> assign(:role_cooldown_rows, [])
        |> assign(:role_cooldown_role_ids, [])
        |> assign(:available_tags, [])
        |> assign(:featured_tag_ids, [])
        |> assign(:base_url, PublicURL.current())

      {:ok, socket |> load_role_cooldown_rows() |> load_tokens() |> load_featured_tags()}
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
  def handle_event("save_role_cooldowns", %{"cooldowns" => cooldown_inputs}, socket)
      when is_map(cooldown_inputs) do
    cooldown_inputs =
      fill_missing_cooldown_inputs(socket.assigns[:role_cooldown_rows] || [], cooldown_inputs)

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

  @impl true
  def handle_event("filter_role_cooldowns", %{"role_filter" => %{"query" => query}}, socket) do
    {:noreply, assign(socket, :role_cooldown_filter, normalize_role_cooldown_filter(query))}
  end

  @impl true
  def handle_event("filter_role_cooldowns", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_role_cooldowns", %{"field" => field}, socket) do
    field = parse_role_cooldown_sort_field(field)
    current_field = socket.assigns[:role_cooldown_sort_by] || :role_name
    current_dir = socket.assigns[:role_cooldown_sort_dir] || :asc

    sort_dir =
      if field == current_field do
        toggle_role_cooldown_sort_dir(current_dir)
      else
        :asc
      end

    {:noreply,
     socket |> assign(:role_cooldown_sort_by, field) |> assign(:role_cooldown_sort_dir, sort_dir)}
  end

  @impl true
  def handle_event("sort_role_cooldowns", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_featured_tags", params, socket) do
    tag_ids = normalize_featured_tag_ids(Map.get(params, "featured_tag_ids", []))

    case Tags.set_featured_tags(tag_ids) do
      {:ok, _tags} ->
        {:noreply, socket |> load_featured_tags() |> put_flash(:info, "Featured tags saved")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save featured tags")}
    end
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

  defp load_featured_tags(socket) do
    tags = Tags.list_all()

    featured_tag_ids =
      tags
      |> Enum.filter(& &1.featured)
      |> Enum.map(&Integer.to_string(&1.id))

    socket
    |> assign(:available_tags, tags)
    |> assign(:featured_tag_ids, featured_tag_ids)
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
            cooldown_seconds: Map.get(cooldowns, role_id)
          }
        end)
      end)
      |> Enum.filter(&(is_binary(&1.role_id) and &1.role_id != ""))
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
          cooldown_seconds: Map.get(cooldowns, role_id)
        }
      end)

    rows =
      (cached_rows ++ uncached_rows)
      |> Enum.sort_by(&role_cooldown_sort_key/1)

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

  defp normalize_role_cooldown_filter(value) when is_binary(value), do: String.trim(value)
  defp normalize_role_cooldown_filter(_), do: ""

  defp filtered_role_cooldown_rows(rows, filter_query) do
    query =
      filter_query
      |> normalize_role_cooldown_filter()
      |> String.downcase()

    if query == "" do
      rows
    else
      Enum.filter(rows, fn row ->
        [row.role_name, row.role_id, row.guild_name]
        |> Enum.map(&((&1 || "") |> to_string() |> String.downcase()))
        |> Enum.any?(&String.contains?(&1, query))
      end)
    end
  end

  defp role_cooldown_sort_key(row) do
    {
      String.downcase(row.role_name || ""),
      String.downcase(row.guild_name || ""),
      row.role_id || ""
    }
  end

  defp fill_missing_cooldown_inputs(rows, cooldown_inputs) do
    Enum.reduce(rows, cooldown_inputs, fn row, acc ->
      if Map.has_key?(acc, row.role_id) do
        acc
      else
        Map.put(acc, row.role_id, cooldown_input_value(row.cooldown_seconds))
      end
    end)
  end

  defp cooldown_input_value(value) when is_integer(value) and value > 0,
    do: Integer.to_string(value)

  defp cooldown_input_value(_), do: ""

  defp parse_role_cooldown_sort_field(field) when is_binary(field) do
    case Enum.find(@role_cooldown_sort_fields, &(Atom.to_string(&1) == field)) do
      nil -> :role_name
      parsed_field -> parsed_field
    end
  end

  defp parse_role_cooldown_sort_field(field) when field in @role_cooldown_sort_fields, do: field
  defp parse_role_cooldown_sort_field(_), do: :role_name

  defp toggle_role_cooldown_sort_dir(:asc), do: :desc
  defp toggle_role_cooldown_sort_dir(:desc), do: :asc
  defp toggle_role_cooldown_sort_dir(_), do: :asc

  defp sorted_role_cooldown_rows(rows, sort_by, sort_dir) do
    field = parse_role_cooldown_sort_field(sort_by)
    dir = if sort_dir == :desc, do: :desc, else: :asc

    sorted = Enum.sort_by(rows, &role_cooldown_field_sort_key(&1, field))

    if dir == :desc do
      Enum.reverse(sorted)
    else
      sorted
    end
  end

  defp role_cooldown_field_sort_key(row, :guild_name) do
    {String.downcase(row.guild_name || ""), String.downcase(row.role_name || ""),
     row.role_id || ""}
  end

  defp role_cooldown_field_sort_key(row, :role_name) do
    {String.downcase(row.role_name || ""), String.downcase(row.guild_name || ""),
     row.role_id || ""}
  end

  defp role_cooldown_field_sort_key(row, :role_id) do
    {row.role_id || "", String.downcase(row.role_name || ""),
     String.downcase(row.guild_name || "")}
  end

  defp role_cooldown_field_sort_key(row, :cooldown_seconds) do
    {row.cooldown_seconds || 0, String.downcase(row.role_name || ""), row.role_id || ""}
  end

  defp role_cooldown_field_sort_key(row, _), do: role_cooldown_field_sort_key(row, :role_name)

  defp role_cooldown_sort_indicator(sort_by, sort_dir, field) do
    if parse_role_cooldown_sort_field(sort_by) == field do
      if sort_dir == :desc, do: "v", else: "^"
    else
      "-"
    end
  end

  defp normalize_featured_tag_ids(tag_ids) when is_list(tag_ids), do: tag_ids
  defp normalize_featured_tag_ids(tag_id) when is_binary(tag_id), do: [tag_id]
  defp normalize_featured_tag_ids(_), do: []

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <h1 class="text-2xl font-bold text-gray-800 dark:text-gray-100">Settings</h1>

      <section aria-labelledby="featured-tags-heading" class="space-y-3">
        <header class="space-y-1">
          <h2
            id="featured-tags-heading"
            class="text-xl font-semibold text-gray-800 dark:text-gray-100"
          >
            Featured Tags
          </h2>

          <p class="text-sm text-gray-600 dark:text-gray-400">
            Featured tags show at the top of the Sounds page above the regular tag filters.
          </p>
        </header>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-4">
          <%= if @available_tags == [] do %>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              No tags are available yet. Add tags to sounds first.
            </p>
          <% else %>
            <form phx-submit="save_featured_tags" class="space-y-4">
              <div class="max-h-64 overflow-y-auto rounded-md border border-gray-200 dark:border-gray-700 p-3">
                <div class="flex flex-wrap gap-2">
                  <%= for tag <- @available_tags do %>
                    <label class="inline-flex items-center gap-2 rounded-full bg-gray-100 dark:bg-gray-700 px-3 py-1 text-sm text-gray-700 dark:text-gray-200">
                      <input
                        type="checkbox"
                        name="featured_tag_ids[]"
                        value={tag.id}
                        checked={Integer.to_string(tag.id) in @featured_tag_ids}
                        class="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600 dark:border-gray-600 dark:focus:ring-offset-gray-800"
                      />
                      <span>{tag.name}</span>
                    </label>
                  <% end %>
                </div>
              </div>

              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-md font-medium hover:bg-blue-700 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
              >
                Save Featured Tags
              </button>
            </form>
          <% end %>
        </div>
      </section>

      <section aria-labelledby="role-cooldowns-heading" class="space-y-3">
        <header class="space-y-1">
          <h2
            id="role-cooldowns-heading"
            class="text-xl font-semibold text-gray-800 dark:text-gray-100"
          >
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
            <% filtered_rows = filtered_role_cooldown_rows(@role_cooldown_rows, @role_cooldown_filter) %> <% sorted_rows =
              sorted_role_cooldown_rows(
                filtered_rows,
                @role_cooldown_sort_by,
                @role_cooldown_sort_dir
              ) %>
            <form phx-change="filter_role_cooldowns" class="max-w-md">
              <label
                for="role-cooldown-filter"
                class="block text-sm font-medium text-gray-700 dark:text-gray-300"
              >
                Filter roles
              </label>
              <input
                id="role-cooldown-filter"
                name="role_filter[query]"
                type="text"
                value={@role_cooldown_filter}
                placeholder="Type to filter roles..."
                phx-debounce="200"
                class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-700 shadow-sm dark:bg-gray-900 dark:text-gray-100 focus:border-blue-500 focus:ring-blue-500"
              />
            </form>

            <form phx-submit="save_role_cooldowns" class="space-y-4">
              <%= if filtered_rows == [] do %>
                <p class="text-sm text-gray-600 dark:text-gray-400">No roles match that filter.</p>
              <% else %>
                <div class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700 text-sm">
                    <thead class="bg-gray-50 dark:bg-gray-900">
                      <tr>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                          <button
                            type="button"
                            phx-click="sort_role_cooldowns"
                            phx-value-field="guild_name"
                            class="inline-flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-200"
                          >
                            Guild
                            <span aria-hidden="true">
                              {role_cooldown_sort_indicator(
                                @role_cooldown_sort_by,
                                @role_cooldown_sort_dir,
                                :guild_name
                              )}
                            </span>
                          </button>
                        </th>

                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                          <button
                            type="button"
                            phx-click="sort_role_cooldowns"
                            phx-value-field="role_name"
                            class="inline-flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-200"
                          >
                            Role
                            <span aria-hidden="true">
                              {role_cooldown_sort_indicator(
                                @role_cooldown_sort_by,
                                @role_cooldown_sort_dir,
                                :role_name
                              )}
                            </span>
                          </button>
                        </th>

                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                          <button
                            type="button"
                            phx-click="sort_role_cooldowns"
                            phx-value-field="role_id"
                            class="inline-flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-200"
                          >
                            Role ID
                            <span aria-hidden="true">
                              {role_cooldown_sort_indicator(
                                @role_cooldown_sort_by,
                                @role_cooldown_sort_dir,
                                :role_id
                              )}
                            </span>
                          </button>
                        </th>

                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                          <button
                            type="button"
                            phx-click="sort_role_cooldowns"
                            phx-value-field="cooldown_seconds"
                            class="inline-flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-200"
                          >
                            Cooldown (seconds)
                            <span aria-hidden="true">
                              {role_cooldown_sort_indicator(
                                @role_cooldown_sort_by,
                                @role_cooldown_sort_dir,
                                :cooldown_seconds
                              )}
                            </span>
                          </button>
                        </th>
                      </tr>
                    </thead>

                    <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                      <%= for row <- sorted_rows do %>
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
              <% end %>

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
              Upload endpoint: <code class="font-mono">POST /api/sounds</code>. Required fields: <code class="font-mono">name</code>, <code class="font-mono">tags</code>,
              plus either <code class="font-mono">file</code>
              (local multipart)
              or <code class="font-mono">url</code>
              (<code class="font-mono">source_type=url</code>). Optional:
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
