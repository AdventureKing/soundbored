defmodule SoundboardWeb.Components.Soundboard.DeleteModal do
  @moduledoc """
  The delete modal component.
  """
  use Phoenix.Component

  def delete_modal(assigns) do
    ~H"""
    <%= if @show_delete_confirm do %>
      <div class="bb-modal-overlay" phx-window-keydown="close_modal_key" phx-key="Escape">
        <div class="bb-modal-scroll">
          <div class="bb-modal-wrap">
            <div class="bb-modal-panel">
              <div class="bb-modal-close-wrap">
                <button phx-click="hide_delete_confirm" type="button" class="bb-modal-close-btn">
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
                <h3 class="bb-modal-title">Delete Sound</h3>

                <p class="bb-section-copy">
                  Are you sure you want to delete this sound? This action cannot be undone.
                </p>

                <div class="bb-modal-actions">
                  <button phx-click="hide_delete_confirm" class="bb-modal-btn-secondary">
                    Cancel
                  </button>
                  <button phx-click="delete_sound" class="bb-modal-btn-danger">
                    Delete
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
