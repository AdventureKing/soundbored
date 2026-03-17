defmodule SoundboardWeb.Components.Soundboard.UploadModal do
  @moduledoc """
  The upload modal component.
  """
  use Phoenix.Component
  alias SoundboardWeb.Components.Soundboard.{TagComponents, VolumeControl}

  def upload_modal(assigns) do
    ~H"""
    <div class="bb-modal-overlay" phx-window-keydown="close_modal_key" phx-key="Escape">
      <div class="bb-modal-scroll">
        <div class="bb-modal-wrap">
          <div class="bb-modal-panel">
            <div class="bb-modal-close-wrap">
              <button phx-click="close_upload_modal" type="button" class="bb-modal-close-btn">
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
              <h3 class="bb-modal-title">Add Sound</h3>
              <form
                phx-submit="save_upload"
                phx-change="validate_upload"
                id="upload-form"
                class="bb-modal-form"
              >
                <% source_ready = source_input_ready?(@source_type, @uploads.audio.entries, @url) %>
                <% form_ready =
                  form_ready?(@source_type, @uploads.audio.entries, @url, @upload_error) %>
                <% local_upload_pending = local_upload_pending?(@source_type, @uploads.audio.entries) %>
                <% url_upload_pending = url_upload_pending?(@source_type, @url) %>

                <div class="bb-field">
                  <label class="bb-label">Source Type</label>
                  <select name="source_type" phx-change="change_source_type" class="bb-input">
                    <option value="local" selected={@source_type == "local"}>Local File</option>
                    <option value="url" selected={@source_type == "url"}>URL</option>
                  </select>
                </div>

                <%= if @source_type == "local" do %>
                  <div class="bb-field">
                    <label class="bb-label">File</label>
                    <.live_file_input
                      upload={@uploads.audio}
                      id="upload-audio-input"
                      class="bb-file-input"
                    />
                  </div>
                <% else %>
                  <div class="bb-field">
                    <label class="bb-label">URL</label>
                    <input
                      type="url"
                      name="url"
                      value={@url}
                      required
                      id="upload-url-input"
                      placeholder="https://example.com/sound.mp3"
                      phx-change="validate_upload"
                      phx-debounce="400"
                      class="bb-input"
                    />
                  </div>
                <% end %>

                <VolumeControl.volume_control
                  id="upload-volume-control"
                  value={@upload_volume}
                  target="upload"
                  label="Clip Volume"
                  preview_label="Preview Clip"
                  preview_disabled={!source_ready}
                  data-preview-kind={if(@source_type == "local", do: "local-upload", else: "url")}
                  data-file-input-id="upload-audio-input"
                  data-url-input-id="upload-url-input"
                  data-preview-src={if(@source_type == "url", do: @url || "", else: "")}
                />

                <div class="bb-field">
                  <label class="bb-label">Name</label>
                  <input
                    type="text"
                    name="name"
                    value={@upload_name}
                    required
                    placeholder="Sound name"
                    phx-change="validate_upload"
                    phx-debounce="400"
                    disabled={!source_ready}
                    class="bb-input disabled:opacity-50 disabled:cursor-not-allowed"
                  />

                  <%= if local_upload_pending do %>
                    <p class="bb-field-help">Select a file first to name it.</p>
                  <% end %>

                  <%= if url_upload_pending do %>
                    <p class="bb-field-help">Enter a URL first to name it.</p>
                  <% end %>

                  <%= if @upload_error do %>
                    <p class="bb-field-error">{@upload_error}</p>
                  <% end %>
                </div>

                <div class="bb-field">
                  <label class="bb-label">Tags</label>
                  <p class="bb-field-help">At least one tag is required.</p>

                  <TagComponents.tag_badge_list tags={@upload_tags} remove_event="remove_upload_tag" />
                  <div class="mt-2 relative">
                    <TagComponents.tag_input_field
                      value={@upload_tag_input}
                      placeholder="Type a tag and press Enter or Tab..."
                      name="upload_tag_input"
                      input_id="upload-tag-input"
                      disabled={!source_ready}
                      phx-keyup="upload_tag_input"
                      phx-keydown="add_upload_tag"
                      onkeydown="
                        if(event.key === 'Enter' || event.key === 'Tab') {
                          event.preventDefault();
                        }
                      "
                      class="disabled:opacity-50 disabled:cursor-not-allowed"
                      autocomplete="off"
                    />

                    <TagComponents.tag_suggestions_dropdown
                      tag_input={@upload_tag_input}
                      tag_suggestions={@upload_tag_suggestions}
                      select_event="select_upload_tag"
                    />
                  </div>
                </div>

                <div class="bb-field bb-check-group">
                  <label class="bb-check-row">
                    <input
                      type="checkbox"
                      name="is_join_sound"
                      value="true"
                      checked={@is_join_sound}
                      phx-click="toggle_join_sound"
                      disabled={!source_ready}
                      class="bb-check"
                    />
                    <span>Play when I join voice</span>
                  </label>
                  <label class="bb-check-row">
                    <input
                      type="checkbox"
                      name="is_leave_sound"
                      value="true"
                      checked={@is_leave_sound}
                      phx-click="toggle_leave_sound"
                      disabled={!source_ready}
                      class="bb-check"
                    />
                    <span>Play when I leave voice</span>
                  </label>
                </div>

                <div class="bb-modal-actions">
                  <button
                    type="submit"
                    phx-disable-with="Adding..."
                    disabled={!form_ready}
                    class="bb-modal-btn-primary"
                  >
                    Add Sound
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp source_input_ready?("local", entries, _url), do: entries != []
  defp source_input_ready?("url", _entries, url), do: String.trim(url || "") != ""
  defp source_input_ready?(_, _entries, _url), do: false

  defp form_ready?(source_type, entries, url, upload_error) do
    source_input_ready?(source_type, entries, url) and is_nil(upload_error)
  end

  defp local_upload_pending?(source_type, entries), do: source_type == "local" and entries == []

  defp url_upload_pending?(source_type, url),
    do: source_type == "url" and String.trim(url || "") == ""
end
