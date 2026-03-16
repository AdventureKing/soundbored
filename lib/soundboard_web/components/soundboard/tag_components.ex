defmodule SoundboardWeb.Components.Soundboard.TagComponents do
  @moduledoc """
  Shared tag UI helpers for the soundboard modals.
  """
  use Phoenix.Component
  alias SoundboardWeb.Live.Support.LiveTags

  attr :tags, :list, default: []
  attr :remove_event, :string, required: true
  attr :tag_key, :atom, default: :name
  attr :wrapper_class, :string, default: "mt-2 flex flex-wrap gap-2"

  def tag_badge_list(assigns) do
    assigns = assign_new(assigns, :tag_key, fn -> :name end)

    ~H"""
    <div class={@wrapper_class}>
      <%= for tag <- @tags do %>
        <% tag_name = tag_value(tag, @tag_key) %>
        <span class="bb-modal-tag-badge">
          {tag_name}
          <button
            type="button"
            phx-click={@remove_event}
            phx-value-tag={tag_name}
            class="bb-modal-tag-remove"
          >
            <svg class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
            </svg>
          </button>
        </span>
      <% end %>
    </div>
    """
  end

  attr :tag_input, :string, default: ""
  attr :tag_suggestions, :list, default: []
  attr :select_event, :string, required: true
  attr :tag_key, :atom, default: :name

  attr :wrapper_class, :string,
    default:
      "absolute z-10 mt-1 w-full rounded-md border border-[rgba(255,255,255,0.18)] bg-[#1e2027] shadow-lg max-h-60 py-1 overflow-auto"

  attr :suggestion_class, :string,
    default: "w-full text-left px-4 py-2 text-sm text-[#e2e0d8] hover:bg-[#16181e]"

  def tag_suggestions_dropdown(assigns) do
    assigns = assign_new(assigns, :tag_input, fn -> "" end)

    ~H"""
    <%= if String.trim(@tag_input || "") != "" and @tag_suggestions != [] do %>
      <div class={@wrapper_class}>
        <%= for tag <- @tag_suggestions do %>
          <% tag_name = tag_value(tag, @tag_key) %>
          <button
            type="button"
            phx-click={@select_event}
            phx-value-tag={tag_name}
            class={@suggestion_class}
          >
            {tag_name}
          </button>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :tag, :any, required: true
  attr :selected_tags, :list, required: true
  attr :uploaded_files, :list, required: true
  attr :tag_key, :atom, default: :name
  attr :click_event, :string, default: "toggle_tag_filter"
  attr :class, :any, default: []

  def tag_filter_button(assigns) do
    assigns = assign_new(assigns, :tag_key, fn -> :name end)

    ~H"""
    <button
      phx-click={@click_event}
      phx-value-tag={tag_value(@tag, @tag_key)}
      class={[
        "inline-flex items-center gap-1 rounded-full px-3 py-1 text-sm font-medium",
        if(LiveTags.tag_selected?(@tag, @selected_tags),
          do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300",
          else:
            "bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700"
        )
        | List.wrap(@class)
      ]}
    >
      {tag_value(@tag, @tag_key)}
      <span class="text-xs">({LiveTags.count_sounds_with_tag(@uploaded_files, @tag)})</span>
    </button>
    """
  end

  attr :value, :string, default: ""
  attr :name, :string, default: nil
  attr :placeholder, :string, default: "Type a tag and press Enter..."
  attr :input_id, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :class, :string, default: ""
  attr :onkeydown, :string, default: nil
  attr :autocomplete, :string, default: nil
  attr :rest, :global

  def tag_input_field(assigns) do
    assigns = assign_new(assigns, :value, fn -> "" end)

    base_class = "bb-input"

    assigns = assign(assigns, :base_class, base_class)

    ~H"""
    <input
      type="text"
      value={@value}
      name={@name}
      placeholder={@placeholder}
      id={@input_id}
      disabled={@disabled}
      class={[@base_class, @class]}
      onkeydown={@onkeydown}
      autocomplete={@autocomplete}
      {@rest}
    />
    """
  end

  defp tag_value(tag, tag_key) when is_atom(tag_key) do
    case tag do
      %{^tag_key => value} -> value
      %{} -> Map.get(tag, :name) || tag
      _ -> tag
    end
  end

  defp tag_value(tag, _tag_key), do: tag
end
