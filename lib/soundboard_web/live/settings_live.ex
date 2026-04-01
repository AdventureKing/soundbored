defmodule SoundboardWeb.SettingsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  alias Soundboard.Accounts.{ApiTokens, Permissions, RoleCooldowns}
  alias Soundboard.AudioPlayer.CommercialScheduler
  alias Soundboard.{Commercials, PublicURL}
  alias Soundboard.Discord.GuildCache
  alias Soundboard.Sounds.Tags
  @role_cooldown_sort_fields [:guild_name, :role_name, :role_id, :cooldown_seconds]

  @impl true
  def mount(_params, session, socket) do
    preview_mode = Map.get(socket.assigns, :live_action) == :preview
    current_user = get_user_from_session(session)

    if preview_mode || Permissions.can_manage_settings?(current_user) do
      socket =
        socket
        |> mount_presence(session)
        |> assign(:current_path, if(preview_mode, do: "/preview/settings", else: "/settings"))
        |> assign(:preview_mode, preview_mode)
        |> assign(:current_user, current_user)
        |> assign(:tokens, [])
        |> assign(:new_token, nil)
        |> assign(:example_token, nil)
        |> assign(:role_cooldown_filter, "")
        |> assign(:role_cooldown_sort_by, :role_name)
        |> assign(:role_cooldown_sort_dir, :asc)
        |> assign(:role_cooldown_rows, [])
        |> assign(:role_cooldown_role_ids, [])
        |> assign(:available_tags, [])
        |> assign(:featured_tag_ids, [])
        |> assign(:collapsed_sections, default_collapsed_sections())
        |> assign(:base_url, PublicURL.current())
        |> assign(:commercial_settings, %Commercials.Settings{})
        |> assign(:commercial_clips, [])
        |> assign(:commercial_upload_name, "")
        |> assign(:commercial_upload_error, nil)
        |> allow_upload(:commercial_audio,
          accept: ~w(audio/mpeg audio/wav audio/ogg audio/x-m4a),
          max_entries: 1,
          max_file_size: 25_000_000
        )

      {:ok,
       socket
       |> load_role_cooldown_rows()
       |> load_tokens()
       |> load_featured_tags()
       |> load_commercial_data()}
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
  def handle_event("toggle_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, :collapsed_sections, toggle_section(socket.assigns[:collapsed_sections], section))}
  end

  @impl true
  def handle_event("create_token", _params, %{assigns: %{preview_mode: true}} = socket) do
    {:noreply, put_flash(socket, :info, "Preview mode: token changes are disabled")}
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
  def handle_event("revoke_token", _params, %{assigns: %{preview_mode: true}} = socket) do
    {:noreply, put_flash(socket, :info, "Preview mode: token changes are disabled")}
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
  def handle_event("save_role_cooldowns", _params, %{assigns: %{preview_mode: true}} = socket) do
    {:noreply, put_flash(socket, :info, "Preview mode: role cooldown changes are disabled")}
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
  def handle_event("save_featured_tags", _params, %{assigns: %{preview_mode: true}} = socket) do
    {:noreply, put_flash(socket, :info, "Preview mode: featured tag changes are disabled")}
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

  @impl true
  def handle_event("save_commercial_settings", _params, %{assigns: %{preview_mode: true}} = socket) do
    {:noreply, put_flash(socket, :info, "Preview mode: commercial changes are disabled")}
  end

  @impl true
  def handle_event("save_commercial_settings", params, socket) do
    attrs = %{
      enabled: Map.get(params, "enabled") == "true",
      inactivity_seconds: parse_positive_integer(Map.get(params, "inactivity_seconds"), 360),
      interval_seconds: parse_positive_integer(Map.get(params, "interval_seconds"), 360)
    }

    case Commercials.save_settings(attrs) do
      {:ok, _settings} ->
        CommercialScheduler.reload()
        {:noreply, socket |> load_commercial_data() |> put_flash(:info, "Commercial settings saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save commercial settings")}
    end
  end

  @impl true
  def handle_event("validate_commercial", params, socket) do
    name = Map.get(params, "commercial_name", "")
    {:noreply, assign(socket, :commercial_upload_name, name)}
  end

  @impl true
  def handle_event("upload_commercial", _params, %{assigns: %{preview_mode: true}} = socket) do
    {:noreply, put_flash(socket, :info, "Preview mode: commercial uploads are disabled")}
  end

  @impl true
  def handle_event("upload_commercial", params, socket) do
    name = String.trim(Map.get(params, "commercial_name", ""))

    if name == "" do
      {:noreply, assign(socket, :commercial_upload_error, "Name is required")}
    else
      result =
        consume_uploaded_entries(socket, :commercial_audio, fn %{path: src_path}, entry ->
          case Commercials.create_clip(name, src_path, entry.client_name) do
            {:ok, clip} -> {:ok, clip}
            {:error, reason} -> {:postpone, reason}
          end
        end)

      case result do
        [_ | _] ->
          CommercialScheduler.reload()

          {:noreply,
           socket
           |> assign(:commercial_upload_name, "")
           |> assign(:commercial_upload_error, nil)
           |> load_commercial_data()
           |> put_flash(:info, "Commercial clip uploaded")}

        [] ->
          {:noreply, assign(socket, :commercial_upload_error, "Please select a file")}
      end
    end
  end

  @impl true
  def handle_event("delete_commercial_clip", %{"id" => id}, %{assigns: %{preview_mode: true}} = socket) do
    _ = id
    {:noreply, put_flash(socket, :info, "Preview mode: commercial changes are disabled")}
  end

  @impl true
  def handle_event("delete_commercial_clip", %{"id" => id}, socket) do
    clip = Enum.find(socket.assigns.commercial_clips, &(to_string(&1.id) == id))

    if clip do
      Commercials.delete_clip(clip)
      CommercialScheduler.reload()
      {:noreply, socket |> load_commercial_data() |> put_flash(:info, "Clip deleted")}
    else
      {:noreply, socket}
    end
  end

  defp load_commercial_data(socket) do
    socket
    |> assign(:commercial_settings, Commercials.get_settings())
    |> assign(:commercial_clips, Commercials.list_clips())
  end

  defp parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  defp parse_positive_integer(_, default), do: default

  defp load_tokens(%{assigns: %{current_user: nil}} = socket) do
    socket
    |> assign(:tokens, [])
    |> assign(:example_token, socket.assigns[:new_token] || socket.assigns[:example_token] || nil)
  end

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

  defp default_collapsed_sections do
    %{
      featured_tags: false,
      role_cooldowns: false,
      commercials: false,
      api_tokens: false
    }
  end

  defp toggle_section(collapsed_sections, section) do
    atom_key =
      case section do
        "featured_tags" -> :featured_tags
        "role_cooldowns" -> :role_cooldowns
        "commercials" -> :commercials
        "api_tokens" -> :api_tokens
        _ -> nil
      end

    if atom_key do
      Map.update(collapsed_sections || default_collapsed_sections(), atom_key, true, &(!&1))
    else
      collapsed_sections || default_collapsed_sections()
    end
  end

  defp section_collapsed?(collapsed_sections, key) when is_atom(key) do
    Map.get(collapsed_sections || default_collapsed_sections(), key, false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bb-view">
      <h1 class="bb-view-title">Settings</h1>
      
      <section aria-labelledby="featured-tags-heading" class="bb-section-card">
        <header class="bb-section-header">
          <div>
            <h2
              id="featured-tags-heading"
              class="bb-section-heading"
            >
              Featured Tags
            </h2>

            <p class="bb-section-copy">
              Featured tags show at the top of the Sounds page above the regular tag filters.
            </p>
          </div>

          <button
            type="button"
            phx-click="toggle_section"
            phx-value-section="featured_tags"
            class="bb-section-toggle"
            aria-controls="featured-tags-content"
            aria-expanded={to_string(!section_collapsed?(@collapsed_sections, :featured_tags))}
            title={if section_collapsed?(@collapsed_sections, :featured_tags), do: "Expand section", else: "Collapse section"}
          >
            <.icon
              name={if section_collapsed?(@collapsed_sections, :featured_tags), do: "hero-chevron-down", else: "hero-chevron-up"}
              class="h-4 w-4"
            />
          </button>
        </header>

        <%= unless section_collapsed?(@collapsed_sections, :featured_tags) do %>
          <div id="featured-tags-content" class="bb-form-stack">
            <%= if @available_tags == [] do %>
              <p class="bb-empty-copy">
                No tags are available yet. Add tags to sounds first.
              </p>
            <% else %>
              <form phx-submit="save_featured_tags" class="bb-form-stack">
                <div class="bb-table-shell max-h-64 overflow-y-auto p-3">
                  <div class="flex flex-wrap gap-2">
                    <%= for tag <- @available_tags do %>
                      <label class="bb-checkbox-chip">
                        <input
                          type="checkbox"
                          name="featured_tag_ids[]"
                          value={tag.id}
                          checked={Integer.to_string(tag.id) in @featured_tag_ids}
                          class="h-4 w-4"
                        /> <span>{tag.name}</span>
                      </label>
                    <% end %>
                  </div>
                </div>

                <button
                  type="submit"
                  class="bb-btn primary"
                >
                  Save Featured Tags
                </button>
              </form>
            <% end %>
          </div>
        <% end %>
      </section>
      
      <section aria-labelledby="role-cooldowns-heading" class="bb-section-card">
        <header class="bb-section-header">
          <div>
            <h2
              id="role-cooldowns-heading"
              class="bb-section-heading"
            >
              Role Cooldowns
            </h2>

            <p class="bb-section-copy">
              Set playback cooldowns per Discord role. Users with multiple roles get the lowest cooldown.
              Default cooldown is 10 minutes.
            </p>
          </div>

          <button
            type="button"
            phx-click="toggle_section"
            phx-value-section="role_cooldowns"
            class="bb-section-toggle"
            aria-controls="role-cooldowns-content"
            aria-expanded={to_string(!section_collapsed?(@collapsed_sections, :role_cooldowns))}
            title={if section_collapsed?(@collapsed_sections, :role_cooldowns), do: "Expand section", else: "Collapse section"}
          >
            <.icon
              name={if section_collapsed?(@collapsed_sections, :role_cooldowns), do: "hero-chevron-down", else: "hero-chevron-up"}
              class="h-4 w-4"
            />
          </button>
        </header>

        <%= unless section_collapsed?(@collapsed_sections, :role_cooldowns) do %>
          <div id="role-cooldowns-content" class="bb-form-stack">
            <%= if @role_cooldown_rows == [] do %>
              <p class="bb-empty-copy">
                No guild roles are available in cache yet. Keep the bot connected to Discord, then refresh.
              </p>
            <% else %>
              <% filtered_rows = filtered_role_cooldown_rows(@role_cooldown_rows, @role_cooldown_filter) %> <% sorted_rows =
                sorted_role_cooldown_rows(
                  filtered_rows,
                  @role_cooldown_sort_by,
                  @role_cooldown_sort_dir
                ) %>
              <form phx-change="filter_role_cooldowns" class="max-w-md bb-form-stack">
                <label
                  for="role-cooldown-filter"
                  class="bb-field-label"
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
                  class="bb-input"
                />
              </form>

              <form phx-submit="save_role_cooldowns" class="bb-form-stack">
                <%= if filtered_rows == [] do %>
                  <p class="bb-empty-copy">No roles match that filter.</p>
                <% else %>
                  <div class="bb-table-shell">
                    <table class="bb-table">
                      <thead>
                        <tr>
                          <th>
                            <button
                              type="button"
                              phx-click="sort_role_cooldowns"
                              phx-value-field="guild_name"
                              class="bb-sort-btn"
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

                          <th>
                            <button
                              type="button"
                              phx-click="sort_role_cooldowns"
                              phx-value-field="role_name"
                              class="bb-sort-btn"
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

                          <th>
                            <button
                              type="button"
                              phx-click="sort_role_cooldowns"
                              phx-value-field="role_id"
                              class="bb-sort-btn"
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

                          <th>
                            <button
                              type="button"
                              phx-click="sort_role_cooldowns"
                              phx-value-field="cooldown_seconds"
                              class="bb-sort-btn"
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

                      <tbody>
                        <%= for row <- sorted_rows do %>
                          <tr>
                            <td>{row.guild_name}</td>

                            <td>{row.role_name}</td>

                            <td class="bb-mono">{row.role_id}</td>

                            <td>
                              <input
                                type="number"
                                min="0"
                                step="1"
                                inputmode="numeric"
                                name={"cooldowns[#{row.role_id}]"}
                                value={row.cooldown_seconds || ""}
                                class="bb-input"
                              />
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                <% end %>

                <p class="bb-muted-note">
                  Leave blank (or set to 0) to use the default cooldown (10 minutes) for that role.
                </p>

                <button
                  type="submit"
                  class="bb-btn primary"
                >
                  Save Cooldowns
                </button>
              </form>
            <% end %>
          </div>
        <% end %>
      </section>
      
      <section aria-labelledby="commercials-heading" class="bb-section-card">
        <header class="bb-section-header">
          <div>
            <h2 id="commercials-heading" class="bb-section-heading">Commercials</h2>
            <p class="bb-section-copy">
              Play a random commercial clip after a period of voice channel inactivity.
              Only plays when users are in the channel.
            </p>
          </div>
          <button
            phx-click="toggle_section"
            phx-value-section="commercials"
            class="bb-section-toggle"
            aria-controls="commercials-content"
            aria-expanded={to_string(!section_collapsed?(@collapsed_sections, :commercials))}
            title={if section_collapsed?(@collapsed_sections, :commercials), do: "Expand section", else: "Collapse section"}
          >
            <.icon
              name={if section_collapsed?(@collapsed_sections, :commercials), do: "hero-chevron-down", else: "hero-chevron-up"}
              class="bb-section-toggle-icon"
            />
          </button>
        </header>

        <%= unless section_collapsed?(@collapsed_sections, :commercials) do %>
          <div id="commercials-content">
            <form phx-submit="save_commercial_settings" phx-change="save_commercial_settings" class="bb-section-form">
              <div class="bb-field">
                <label class="bb-label">
                  <input
                    type="checkbox"
                    name="enabled"
                    value="true"
                    checked={@commercial_settings.enabled}
                    class="mr-2"
                  />
                  Enable commercials
                </label>
              </div>

              <div class="bb-field">
                <label class="bb-label" for="inactivity_seconds">Inactivity timer (seconds)</label>
                <p class="bb-field-help">How long of silence before the first commercial plays.</p>
                <input
                  id="inactivity_seconds"
                  type="number"
                  name="inactivity_seconds"
                  min="1"
                  step="1"
                  value={@commercial_settings.inactivity_seconds}
                  class="bb-input"
                />
              </div>

              <div class="bb-field">
                <label class="bb-label" for="interval_seconds">Repeat interval (seconds)</label>
                <p class="bb-field-help">How often to play another commercial while the channel stays idle.</p>
                <input
                  id="interval_seconds"
                  type="number"
                  name="interval_seconds"
                  min="1"
                  step="1"
                  value={@commercial_settings.interval_seconds}
                  class="bb-input"
                />
              </div>

              <button type="submit" class="bb-btn bb-btn-primary">Save Settings</button>
            </form>

            <hr class="my-6 border-gray-200 dark:border-gray-700" />

            <h3 class="bb-section-heading mb-4">Commercial Clips</h3>

            <%= if @commercial_clips == [] do %>
              <p class="bb-section-copy mb-4">No commercial clips uploaded yet.</p>
            <% else %>
              <ul class="space-y-2 mb-6">
                <%= for clip <- @commercial_clips do %>
                  <li class="flex items-center justify-between gap-4 rounded-lg border border-gray-200 dark:border-gray-700 px-4 py-2">
                    <span class="text-sm font-medium text-gray-800 dark:text-gray-200"><%= clip.name %></span>
                    <span class="bb-section-copy text-xs"><%= clip.filename %></span>
                    <button
                      type="button"
                      phx-click="delete_commercial_clip"
                      phx-value-id={clip.id}
                      data-confirm={"Delete \"#{clip.name}\"?"}
                      class="bb-btn bb-btn-danger text-sm"
                    >
                      Delete
                    </button>
                  </li>
                <% end %>
              </ul>
            <% end %>

            <form
              phx-submit="upload_commercial"
              phx-change="validate_commercial"
              class="bb-section-form"
            >
              <div class="bb-field">
                <label class="bb-label" for="commercial_name">Clip name</label>
                <input
                  id="commercial_name"
                  type="text"
                  name="commercial_name"
                  value={@commercial_upload_name}
                  placeholder="e.g. BeeBot Ad 1"
                  class="bb-input"
                />
              </div>

              <div class="bb-field">
                <label class="bb-label">Audio file</label>
                <.live_file_input upload={@uploads.commercial_audio} class="bb-input" />
              </div>

              <%= if @commercial_upload_error do %>
                <p class="text-red-500 text-sm mb-2"><%= @commercial_upload_error %></p>
              <% end %>

              <button type="submit" class="bb-btn bb-btn-primary">Upload Clip</button>
            </form>
          </div>
        <% end %>
      </section>

      <section aria-labelledby="api-tokens-heading" class="bb-section-card">
        <header class="bb-section-header">
          <div>
            <h2 id="api-tokens-heading" class="bb-section-heading">API Tokens</h2>

            <p class="bb-section-copy">
              Create a personal token to play sounds remotely. Requests authenticated with a token
              are attributed to your account and update your stats.
            </p>
          </div>

          <button
            type="button"
            phx-click="toggle_section"
            phx-value-section="api_tokens"
            class="bb-section-toggle"
            aria-controls="api-tokens-content"
            aria-expanded={to_string(!section_collapsed?(@collapsed_sections, :api_tokens))}
            title={if section_collapsed?(@collapsed_sections, :api_tokens), do: "Expand section", else: "Collapse section"}
          >
            <.icon
              name={if section_collapsed?(@collapsed_sections, :api_tokens), do: "hero-chevron-down", else: "hero-chevron-up"}
              class="h-4 w-4"
            />
          </button>
        </header>

        <%= unless section_collapsed?(@collapsed_sections, :api_tokens) do %>
          <div id="api-tokens-content" class="bb-form-stack">
            <div class="bb-form-stack">
              <form phx-submit="create_token" class="bb-btn-row">
                <div class="flex-1">
                  <label class="bb-field-label">Label</label>
                  <input
                    name="label"
                    type="text"
                    placeholder="e.g., CI Bot"
                    class="bb-input"
                  />
                </div>

                <button
                  type="submit"
                  class="bb-btn primary"
                >
                  Create
                </button>
              </form>
            </div>

            <div class="bb-table-shell">
              <div class="overflow-x-auto">
                <table class="bb-table">
                  <thead>
                    <tr>
                      <th>Label</th>

                      <th>Token</th>

                      <th>Created</th>

                      <th>Last Used</th>

                      <th></th>
                    </tr>
                  </thead>

                  <tbody>
                    <%= for token <- @tokens do %>
                      <tr>
                        <td>{token.label || "(no label)"}</td>

                        <td>
                          <div class="relative">
                            <button
                              id={"copy-token-#{token.id}"}
                              type="button"
                              phx-hook="CopyButton"
                              data-copy-text={token.token}
                              class="bb-copy-btn"
                            >
                              Copy
                            </button> <pre class="bb-code-block pr-20 whitespace-nowrap"><code class="bb-mono">{token.token}</code></pre>
                          </div>
                        </td>

                        <td class="bb-section-copy">
                          {format_dt(token.inserted_at)}
                        </td>

                        <td class="bb-section-copy">
                          {format_dt(token.last_used_at) || "--"}
                        </td>

                        <td class="text-right">
                          <button
                            phx-click="revoke_token"
                            phx-value-id={token.id}
                            class="bb-btn danger"
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

            <div class="bb-form-stack">
              <h3 class="bb-section-heading">How to call the API</h3>

              <p class="bb-section-copy">
                Include your token in the Authorization header:
                <code class="bb-code-block bb-mono inline-block px-2 py-1">
                  Authorization: Bearer {@example_token || "<token>"}
                </code>
              </p>

              <div class="bb-form-stack">
                <div>
                  <div class="bb-field-label">List sounds</div>

                  <div class="relative">
                    <button
                      id="copy-list-sounds"
                      type="button"
                      phx-hook="CopyButton"
                      data-copy-text={"curl -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds"}
                      class="bb-copy-btn bb-copy-top"
                    >
                      Copy
                    </button> <pre class="bb-code-block mt-1 pr-16 whitespace-nowrap min-h-[56px]"><code class="bb-mono">curl -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds</code></pre>
                  </div>
                </div>

                <div class="bb-muted-note">
                  Upload endpoint: <code class="bb-mono">POST /api/sounds</code>. Required fields: <code class="bb-mono">name</code>, <code class="bb-mono">tags</code>,
                  plus either <code class="bb-mono">file</code>
                  (local multipart)
                  or <code class="bb-mono">url</code>
                  (<code class="bb-mono">source_type=url</code>). Optional:
                  <code class="bb-mono">volume</code>
                  (0-150).
                </div>

                <div>
                  <div class="bb-field-label">Upload local file (multipart/form-data)</div>

                  <div class="relative">
                    <button
                      id="copy-upload-local"
                      type="button"
                      phx-hook="CopyButton"
                      data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" -F \"source_type=local\" -F \"name=<NAME>\" -F \"file=@/path/to/sound.mp3\" -F \"tags[]=meme\" -F \"tags[]=alert\" -F \"volume=90\" #{@base_url}/api/sounds"}
                      class="bb-copy-btn bb-copy-top"
                    >
                      Copy
                    </button> <pre class="bb-code-block mt-1 pr-16 min-h-[120px]"><code class="bb-mono">curl -X POST \
    -H "Authorization: Bearer {(@example_token || "<TOKEN>")}" \
    -F "source_type=local" \
    -F "name=&lt;NAME&gt;" \
    -F "file=@/path/to/sound.mp3" \
    -F "tags[]=meme" \
    -F "tags[]=alert" \
    -F "volume=90" \
    {@base_url}/api/sounds</code></pre>
                  </div>
                </div>

                <div>
                  <div class="bb-field-label">Upload from URL (JSON)</div>

                  <div class="relative">
                    <button
                      id="copy-upload-url"
                      type="button"
                      phx-hook="CopyButton"
                      data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" -H \"Content-Type: application/json\" -d '{\"source_type\":\"url\",\"name\":\"wow\",\"url\":\"https://example.com/wow.mp3\",\"tags\":[\"meme\",\"reaction\"],\"volume\":90}' #{@base_url}/api/sounds"}
                      class="bb-copy-btn bb-copy-top"
                    >
                      Copy
                    </button> <pre class="bb-code-block mt-1 pr-16 min-h-[110px]"><code class="bb-mono">curl -X POST \
    -H "Authorization: Bearer {(@example_token || "<TOKEN>")}" \
    -H "Content-Type: application/json" \
    -d '&#123;"source_type":"url","name":"wow","url":"https://example.com/wow.mp3","tags":["meme","reaction"],"volume":90&#125;' \
    {@base_url}/api/sounds</code></pre>
                  </div>
                </div>

                <div>
                  <div class="bb-field-label">Play a sound by ID</div>

                  <div class="relative">
                    <button
                      id="copy-play-sound"
                      type="button"
                      phx-hook="CopyButton"
                      data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds/<SOUND_ID>/play"}
                      class="bb-copy-btn bb-copy-top"
                    >
                      Copy
                    </button> <pre class="bb-code-block mt-1 pr-16 whitespace-nowrap min-h-[56px]"><code class="bb-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds/&lt;SOUND_ID&gt;/play</code></pre>
                  </div>
                </div>

                <div>
                  <div class="bb-field-label">Stop all sounds</div>

                  <div class="relative">
                    <button
                      id="copy-stop-sounds"
                      type="button"
                      phx-hook="CopyButton"
                      data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds/stop"}
                      class="bb-copy-btn bb-copy-top"
                    >
                      Copy
                    </button> <pre class="bb-code-block mt-1 pr-16 whitespace-nowrap min-h-[56px]"><code class="bb-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds/stop</code></pre>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp format_dt(nil), do: nil
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
