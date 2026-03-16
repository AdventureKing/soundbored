defmodule SoundboardWeb.SoundboardLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  alias SoundboardWeb.Components.Soundboard.{DeleteModal, EditModal, UploadModal}
  import EditModal
  import DeleteModal
  import UploadModal
  alias Soundboard.{Favorites, PlaybackCooldown, PubSubTopics, Sounds}
  alias Soundboard.Accounts.Permissions
  alias SoundboardWeb.Live.SoundboardLive.{EditFlow, UploadFlow}
  alias SoundboardWeb.Live.Support.{FlashHelpers, SoundPlayback}
  alias SoundboardWeb.Soundboard.SoundFilter

  import SoundboardWeb.Live.Support.LiveTags,
    only: [all_tags: 1, featured_tags: 1, tag_selected?: 2]

  import SoundFilter, only: [filter_sounds: 3]

  @impl true
  def mount(_params, session, socket) do
    preview_mode = Map.get(socket.assigns, :live_action) == :preview
    current_user = get_user_from_session(session)

    socket =
      if connected?(socket) do
        PubSubTopics.subscribe_files()
        PubSubTopics.subscribe_playback()
        send(self(), :load_sound_files)
        socket
      else
        socket
      end

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, if(preview_mode, do: "/preview/soundboard", else: "/"))
      |> assign(:preview_mode, preview_mode)
      |> assign(:current_user, current_user)
      |> assign(:can_upload_clips, Permissions.can_upload_clips?(current_user))
      |> assign(:can_manage_settings, Permissions.can_manage_settings?(current_user))
      |> assign_initial_state()
      |> assign_favorites(current_user)
      |> refresh_cooldown_timer()

    if socket.assigns.flash do
      Process.send_after(self(), :clear_flash, 3000)
    end

    {:ok, socket}
  end

  defp assign_initial_state(socket) do
    socket
    |> assign(:uploaded_files, [])
    |> assign(:loading_sounds, true)
    |> assign(:cooldown_end_ms, nil)
    |> assign(:cooldown_remaining_ms, nil)
    |> assign(:search_query, "")
    |> assign(:editing, nil)
    |> assign(:selected_tags, [])
    |> assign(:favorites_only, false)
    |> assign(:show_all_tags, false)
    |> UploadFlow.assign_defaults()
    |> EditFlow.assign_defaults()
    |> allow_upload(:audio,
      accept: ~w(audio/mpeg audio/wav audio/ogg audio/x-m4a),
      max_entries: 1,
      max_file_size: 25_000_000,
      auto_upload: false,
      progress: &handle_progress/3,
      accept_errors: [
        too_large: "File is too large (max 25MB)",
        not_accepted: "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."
      ]
    )
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("change_source_type", %{"source_type" => source_type}, socket) do
    UploadFlow.change_source_type(socket, source_type)
  end

  @impl true
  def handle_event("validate_sound", params, socket) do
    EditFlow.validate_sound(socket, params)
  end

  @impl true
  def handle_event("toggle_tag_list", _params, socket) do
    {:noreply, assign(socket, :show_all_tags, !socket.assigns.show_all_tags)}
  end

  @impl true
  def handle_event("play", %{"name" => filename}, socket) do
    SoundPlayback.play(socket, filename)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("toggle_tag_filter", %{"tag" => tag_name}, socket) do
    case Enum.find(all_tags(socket.assigns.uploaded_files), &(&1.name == tag_name)) do
      nil ->
        {:noreply, socket}

      tag ->
        selected_tags =
          if tag_selected?(tag, socket.assigns.selected_tags) do
            Enum.reject(socket.assigns.selected_tags, &(&1.id == tag.id))
          else
            socket.assigns.selected_tags ++ [tag]
          end

        {:noreply,
         socket
         |> assign(:selected_tags, selected_tags)
         |> assign(:search_query, "")}
    end
  end

  @impl true
  def handle_event("toggle_favorites_filter", _params, socket) do
    {:noreply, assign(socket, :favorites_only, !socket.assigns.favorites_only)}
  end

  @impl true
  def handle_event("clear_tag_filters", _, socket) do
    {:noreply, assign(socket, :selected_tags, [])}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    case preview_mock_sound(socket, id) do
      nil ->
        EditFlow.open_modal(socket, id)

      sound ->
        {:noreply, open_preview_edit_modal(socket, sound)}
    end
  end

  @impl true
  def handle_event("save_upload", params, socket) do
    if can_upload_clips?(socket) do
      UploadFlow.save(socket, params, &Phoenix.LiveView.consume_uploaded_entries/3)
    else
      {:noreply, upload_forbidden_flash(socket)}
    end
  end

  @impl true
  def handle_event("validate_upload", params, socket) do
    UploadFlow.validate(socket, params)
  end

  @impl true
  def handle_event("show_upload_modal", _params, socket) do
    if can_upload_clips?(socket) do
      UploadFlow.show_modal(socket)
    else
      {:noreply, upload_forbidden_flash(socket)}
    end
  end

  @impl true
  def handle_event("hide_upload_modal", _params, socket) do
    UploadFlow.hide_modal(socket)
  end

  @impl true
  def handle_event("add_upload_tag", %{"key" => key} = params, socket) do
    UploadFlow.add_tag(socket, key, Map.get(params, "value", ""))
  end

  @impl true
  def handle_event("remove_upload_tag", %{"tag" => tag_name}, socket) do
    UploadFlow.remove_tag(socket, tag_name)
  end

  @impl true
  def handle_event("select_upload_tag_suggestion", %{"tag" => tag_name}, socket) do
    UploadFlow.select_tag_suggestion(socket, tag_name)
  end

  @impl true
  def handle_event("upload_tag_input", %{"key" => _key} = params, socket) do
    UploadFlow.update_tag_input(socket, Map.get(params, "value", ""))
  end

  @impl true
  def handle_event("add_tag", %{"key" => key} = params, socket) do
    if preview_edit_sound?(socket) do
      {:noreply, put_flash(socket, :info, "Preview mode: edit actions are disabled")}
    else
      EditFlow.add_tag(socket, key, Map.get(params, "value", ""))
    end
  end

  @impl true
  def handle_event("remove_tag", %{"tag" => tag_name}, socket) do
    if preview_edit_sound?(socket) do
      {:noreply, put_flash(socket, :info, "Preview mode: edit actions are disabled")}
    else
      EditFlow.remove_tag(socket, tag_name)
    end
  end

  @impl true
  def handle_event("select_tag_suggestion", %{"tag" => tag_name}, socket) do
    if preview_edit_sound?(socket) do
      {:noreply, put_flash(socket, :info, "Preview mode: edit actions are disabled")}
    else
      EditFlow.select_tag_suggestion(socket, tag_name)
    end
  end

  @impl true
  def handle_event("tag_input", %{"key" => _key} = params, socket) do
    EditFlow.update_tag_input(socket, Map.get(params, "value", ""))
  end

  @impl true
  def handle_event("select_tag", %{"tag" => tag_name}, socket) do
    if preview_edit_sound?(socket) do
      {:noreply, put_flash(socket, :info, "Preview mode: edit actions are disabled")}
    else
      EditFlow.select_tag(socket, tag_name)
    end
  end

  @impl true
  def handle_event("save_sound", params, socket) do
    if preview_edit_sound?(socket) do
      {:noreply, put_flash(socket, :info, "Preview mode: save is disabled")}
    else
      EditFlow.save_sound(socket, params)
    end
  end

  @impl true
  def handle_event("close_upload_modal", _params, socket) do
    UploadFlow.hide_modal(socket)
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> UploadFlow.close_modal()
     |> EditFlow.close_modal()}
  end

  @impl true
  def handle_event("close_modal_key", %{"key" => "Escape"}, socket) do
    edit_open = socket.assigns[:edit_state] && socket.assigns.edit_state.show_modal
    upload_open = socket.assigns[:upload_state] && socket.assigns.upload_state.show_upload_modal

    if edit_open || upload_open do
      handle_event("close_modal", %{}, socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_upload_tag", %{"tag" => tag_name}, socket) do
    UploadFlow.select_tag(socket, tag_name)
  end

  @impl true
  def handle_event("toggle_favorite", %{"sound-id" => sound_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to favorite sounds")}

      user ->
        case Favorites.toggle_favorite(user.id, sound_id) do
          {:ok, _favorite} ->
            {:noreply,
             socket
             |> assign_favorites(user)
             |> put_flash(:info, "Favorites updated!")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Favorites.error_message(reason))}
        end
    end
  end

  @impl true
  def handle_event("show_delete_confirm", _params, socket) do
    if preview_edit_sound?(socket) do
      {:noreply, put_flash(socket, :info, "Preview mode: delete is disabled")}
    else
      EditFlow.show_delete_confirm(socket)
    end
  end

  @impl true
  def handle_event("hide_delete_confirm", _params, socket) do
    EditFlow.hide_delete_confirm(socket)
  end

  @impl true
  def handle_event("delete_sound", _params, socket) do
    if preview_edit_sound?(socket) do
      {:noreply, put_flash(socket, :info, "Preview mode: delete is disabled")}
    else
      EditFlow.delete_sound(socket)
    end
  end

  @impl true
  def handle_event("toggle_join_sound", _params, socket) do
    UploadFlow.toggle_join_sound(socket)
  end

  @impl true
  def handle_event("toggle_leave_sound", _params, socket) do
    UploadFlow.toggle_leave_sound(socket)
  end

  @impl true
  def handle_event("update_volume", %{"volume" => volume, "target" => "edit"}, socket) do
    EditFlow.update_volume(socket, volume)
  end

  @impl true
  def handle_event("update_volume", %{"volume" => volume, "target" => "upload"}, socket) do
    UploadFlow.update_volume(socket, volume)
  end

  @impl true
  def handle_event("update_volume", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("play_random", _params, socket) do
    filtered_sounds =
      socket.assigns.uploaded_files
      |> filter_sounds(socket.assigns.search_query, socket.assigns.selected_tags)
      |> filter_to_favorites(socket.assigns.favorites_only, socket.assigns.favorites)

    case get_random_sound(filtered_sounds) do
      nil ->
        {:noreply, socket}

      sound ->
        SoundPlayback.play(socket, sound.filename)
    end
  end

  @impl true
  def handle_event("stop_sound", _params, socket) do
    # Stop browser-based sounds
    socket = push_event(socket, "stop-all-sounds", %{})

    # Stop Discord bot sounds if user is logged in
    if socket.assigns.current_user do
      Soundboard.AudioPlayer.stop_sound()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("admin_stop_and_clear_queue", _params, socket) do
    if Permissions.can_manage_settings?(socket.assigns[:current_user]) do
      socket =
        socket
        |> push_event("stop-all-sounds", %{})
        |> put_flash(:info, "Stopped all sounds and cleared queue.")

      Soundboard.AudioPlayer.stop_and_clear_queue()
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "You are not allowed to clear the playback queue.")}
    end
  end

  @impl true
  def handle_info({:error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  @impl true
  def handle_info({:sound_played, %{filename: _, played_by: _} = event}, socket) do
    {:noreply,
     socket
     |> FlashHelpers.flash_sound_played(event)
     |> maybe_refresh_cooldown_timer(event.played_by)}
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_info({:files_updated}, socket) do
    {:noreply, load_sound_files(socket)}
  end

  @impl true
  def handle_info(:load_sound_files, socket) do
    {:noreply,
     socket
     |> load_sound_files()
     |> assign(:loading_sounds, false)}
  end

  defp assign_favorites(socket, nil), do: assign(socket, :favorites, [])

  defp assign_favorites(socket, user) do
    favorites = Favorites.list_favorites(user.id)
    assign(socket, :favorites, favorites)
  end

  defp load_sound_files(socket) do
    sounds = Sounds.list_detailed()

    sounds =
      if socket.assigns[:preview_mode] && sounds == [] do
        preview_sounds()
      else
        sounds
      end

    assign(socket, :uploaded_files, sounds)
  end

  defp preview_sounds do
    [
      %{
        id: -1,
        filename: "beebot-sting.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "Demp"},
        tags: [
          %{id: -101, name: "beebot", featured: true},
          %{id: -102, name: "memes", featured: false}
        ]
      },
      %{
        id: -2,
        filename: "ship-me-sooner.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "greydiel"},
        tags: [
          %{id: -103, name: "gorlord", featured: true},
          %{id: -104, name: "hot soup", featured: false}
        ]
      },
      %{
        id: -3,
        filename: "we-sting-for-you.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "beebrother"},
        tags: [
          %{id: -105, name: "beebot", featured: true},
          %{id: -106, name: "reactions", featured: false}
        ]
      },
      %{
        id: -4,
        filename: "queen-beat-drop.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "hive_admin"},
        tags: [
          %{id: -107, name: "beebot", featured: true},
          %{id: -108, name: "hype", featured: false}
        ]
      },
      %{
        id: -5,
        filename: "sticky-situation.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "toasty"},
        tags: [
          %{id: -109, name: "chaos", featured: true},
          %{id: -110, name: "memes", featured: false}
        ]
      },
      %{
        id: -6,
        filename: "pollinate-the-room.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "sprout"},
        tags: [
          %{id: -111, name: "reactions", featured: true},
          %{id: -112, name: "beebot", featured: false}
        ]
      },
      %{
        id: -7,
        filename: "honey-heist-alert.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "buzzed"},
        tags: [
          %{id: -113, name: "alerts", featured: true},
          %{id: -114, name: "gorlord", featured: false}
        ]
      },
      %{
        id: -8,
        filename: "comb-check-one-two.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "dipper"},
        tags: [
          %{id: -115, name: "testing", featured: true},
          %{id: -116, name: "hot soup", featured: false}
        ]
      },
      %{
        id: -9,
        filename: "wax-on-wax-off.mp3",
        source_type: "url",
        url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-9.mp3",
        volume: 1.0,
        preview_mock: true,
        user: %{username: "beesly"},
        tags: [
          %{id: -117, name: "beebot", featured: true},
          %{id: -118, name: "reactions", featured: false}
        ]
      }
    ]
  end

  defp preview_mock_sound(socket, id) do
    if socket.assigns[:preview_mode] do
      Enum.find(socket.assigns[:uploaded_files] || [], fn sound ->
        Map.get(sound, :preview_mock, false) && to_string(sound.id) == to_string(id)
      end)
    else
      nil
    end
  end

  defp open_preview_edit_modal(socket, sound) do
    preview_sound =
      sound
      |> Map.put_new(:tags, [])
      |> Map.put_new(:user_sound_settings, [])
      |> Map.put_new(:internal_cooldown_seconds, 0)
      |> Map.put_new(:source_type, "url")
      |> Map.put_new(:url, "")
      |> Map.put_new(:volume, 1.0)
      |> Map.put_new(:filename, "preview-sound.mp3")
      |> Map.put_new(:user_id, nil)

    edit_state = %EditFlow.State{
      show_modal: true,
      current_sound: preview_sound,
      tag_input: "",
      tag_suggestions: [],
      show_delete_confirm: false,
      edit_name_error: nil,
      current_user_id: nil
    }

    socket
    |> assign(:edit_state, edit_state)
    |> assign(:show_modal, true)
    |> assign(:current_sound, preview_sound)
    |> assign(:tag_input, "")
    |> assign(:tag_suggestions, [])
    |> assign(:show_delete_confirm, false)
    |> assign(:edit_name_error, nil)
  end

  defp preview_edit_sound?(socket) do
    socket.assigns[:preview_mode] &&
      Map.get(socket.assigns[:current_sound] || %{}, :preview_mock, false)
  end

  defp get_random_sound([]), do: nil

  defp get_random_sound(sounds) do
    Enum.random(sounds)
  end

  defp sound_card_dom_id(sound) do
    "sound-card-" <> sound_dom_key(sound)
  end

  defp sound_player_dom_id(sound) do
    "local-play-" <> sound_dom_key(sound)
  end

  defp sound_dom_key(sound) do
    case Map.get(sound, :id) || Map.get(sound, "id") do
      nil ->
        filename = Map.get(sound, :filename) || Map.get(sound, "filename") || inspect(sound)
        "f#{:erlang.phash2(filename, 1_000_000)}"

      id ->
        to_string(id)
    end
  end

  defp filter_to_favorites(sounds, false, _favorite_sound_ids), do: sounds

  defp filter_to_favorites(sounds, true, favorite_sound_ids) do
    favorite_sound_ids = MapSet.new(favorite_sound_ids)
    Enum.filter(sounds, &MapSet.member?(favorite_sound_ids, &1.id))
  end

  defp handle_progress(:audio, _entry, socket) do
    {:noreply, socket}
  end

  defp can_upload_clips?(socket) do
    Permissions.can_upload_clips?(socket.assigns[:current_user])
  end

  defp refresh_cooldown_timer(socket) do
    cooldown_end_ms = PlaybackCooldown.active_cooldown_end_unix_ms(socket.assigns[:current_user])

    socket
    |> assign(:cooldown_end_ms, cooldown_end_ms)
    |> assign(:cooldown_remaining_ms, remaining_ms_from_end(cooldown_end_ms))
  end

  defp maybe_refresh_cooldown_timer(socket, played_by) when is_binary(played_by) do
    case socket.assigns[:current_user] do
      %{username: ^played_by} -> refresh_cooldown_timer(socket)
      _ -> socket
    end
  end

  defp maybe_refresh_cooldown_timer(socket, _played_by), do: socket

  defp remaining_ms_from_end(nil), do: nil

  defp remaining_ms_from_end(end_ms) when is_integer(end_ms) do
    max(end_ms - System.system_time(:millisecond), 0)
  end

  defp upload_forbidden_flash(socket) do
    Phoenix.LiveView.put_flash(
      socket,
      :error,
      "Your Discord role does not allow uploading clips."
    )
  end
end
