defmodule SoundboardWeb.Components.Soundboard.EditModal do
  @moduledoc """
  The edit modal component.
  """
  use Phoenix.Component
  alias Soundboard.Accounts.Permissions
  alias Soundboard.Volume
  alias SoundboardWeb.Components.Soundboard.TagComponents

  attr :flash, :map, default: %{}
  attr :edit_name_error, :string, default: nil
  attr :current_user, :map, required: true
  attr :current_sound, :map, required: true
  attr :tag_input, :string, default: ""
  attr :tag_suggestions, :list, default: []

  def edit_modal(assigns) do
    assigns = assign_new(assigns, :edit_name_error, fn -> nil end)

    assigns =
      update(assigns, :current_sound, fn sound ->
        tags =
          case sound.tags do
            tags when is_list(tags) -> tags
            _ -> []
          end

        Map.put(sound, :tags, tags)
      end)

    ~H"""
    <% volume_percent = Volume.decimal_to_percent(@current_sound.volume) %>
    <div class="bb-modal-overlay" phx-window-keydown="close_modal_key" phx-key="Escape">
      <div class="bb-modal-scroll">
        <div class="bb-modal-wrap">
          <div class="bb-modal-panel">
            <div class="bb-modal-close-wrap">
              <button phx-click="close_modal" type="button" class="bb-modal-close-btn">
                <span class="sr-only">Close</span>
                <svg
                  class="h-5 w-5"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <div class="bb-modal-body">
              <h3 class="bb-modal-title">Edit Sound</h3>

              <form phx-submit="save_sound" phx-change="validate_sound" id="edit-form" class="bb-modal-form">
                <input type="hidden" name="sound_id" value={@current_sound.id} />
                <input type="hidden" name="source_type" value={@current_sound.source_type} />
                <input type="hidden" name="url" value={@current_sound.url} />
                <input type="hidden" name="volume" value={volume_percent} />

                <div class="bb-field">
                  <label class="bb-label">Source</label>
                  <div class="bb-source-box">
                    <%= if @current_sound.source_type == "url" do %>
                      URL: {@current_sound.url}
                    <% else %>
                      Local File
                    <% end %>
                  </div>
                </div>

                <div class="bb-field">
                  <label class="bb-label">Name</label>
                  <input
                    type="text"
                    name="filename"
                    value={
                      String.replace(
                        @current_sound.filename,
                        Path.extname(@current_sound.filename),
                        ""
                      )
                    }
                    required
                    placeholder="Sound name"
                    phx-debounce="400"
                    class={["bb-input", if(@edit_name_error, do: "bb-input-error", else: "")]}
                  />
                  <%= if @edit_name_error do %>
                    <p class="bb-field-error">{@edit_name_error}</p>
                  <% end %>
                </div>

                <%= if Permissions.can_manage_settings?(@current_user) do %>
                  <div class="bb-field">
                    <label class="bb-label">Internal Cooldown (seconds)</label>
                    <input
                      type="number"
                      name="internal_cooldown_seconds"
                      min="0"
                      step="1"
                      value={@current_sound.internal_cooldown_seconds || 0}
                      class="bb-input"
                    />
                    <p class="bb-field-help">
                      Prevent anyone from replaying this clip until the cooldown expires.
                    </p>
                  </div>
                <% end %>

                <div class="bb-field">
                  <label class="bb-label">Tags</label>
                  <TagComponents.tag_badge_list
                    tags={@current_sound.tags}
                    remove_event="remove_tag"
                    wrapper_class="mt-2 flex flex-wrap gap-2"
                  />
                </div>

                <div class="bb-field bb-tag-field">
                  <TagComponents.tag_input_field
                    value={@tag_input}
                    placeholder="Type a tag and press Enter..."
                    input_id="tag-input"
                    phx-keyup="tag_input"
                    phx-keydown="add_tag"
                    class="bb-input"
                    onkeydown="
                      if(event.key === 'Enter') {
                        event.preventDefault();
                        requestAnimationFrame(() => this.value = '');
                        return false;
                      }
                    "
                    autocomplete="off"
                  />

                  <TagComponents.tag_suggestions_dropdown
                    tag_input={@tag_input}
                    tag_suggestions={@tag_suggestions}
                    select_event="select_tag"
                    wrapper_class="absolute z-10 mt-1 w-full rounded-md border border-[rgba(255,255,255,0.18)] bg-[#1e2027] shadow-lg max-h-60 py-1 overflow-auto"
                    suggestion_class="w-full text-left px-4 py-2 text-sm text-[#e2e0d8] hover:bg-[#16181e]"
                  />
                </div>

                <div class="bb-field bb-check-group">
                  <% user_setting =
                    Enum.find(
                      @current_sound.user_sound_settings || [],
                      &(&1.user_id == @current_user.id)
                    ) %>
                  <label class="bb-check-row">
                    <input
                      type="checkbox"
                      name="is_join_sound"
                      value="true"
                      checked={user_setting && user_setting.is_join_sound}
                      class="bb-check"
                    />
                    <span>Play when I join voice</span>
                  </label>
                  <label class="bb-check-row">
                    <input
                      type="checkbox"
                      name="is_leave_sound"
                      value="true"
                      checked={user_setting && user_setting.is_leave_sound}
                      class="bb-check"
                    />
                    <span>Play when I leave voice</span>
                  </label>
                </div>

                <div class="bb-modal-actions">
                  <button type="submit" disabled={@edit_name_error} class="bb-modal-btn-primary">
                    Save Changes
                  </button>
                  <%= if can_delete_sound?(@current_sound, @current_user) do %>
                    <button type="button" phx-click="show_delete_confirm" class="bb-modal-btn-danger">
                      Delete Sound
                    </button>
                  <% end %>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp can_delete_sound?(%{user_id: owner_id}, %{id: user_id} = current_user)
       when is_integer(owner_id) and is_integer(user_id) do
    owner_id == user_id or Permissions.can_manage_settings?(current_user)
  end

  defp can_delete_sound?(_sound, _current_user), do: false
end
