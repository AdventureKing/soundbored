defmodule SoundboardWeb.Soundboard.SoundFilter do
  @moduledoc """
  Filters sounds based on the selected tags and search query.
  """

  def filter_sounds(sounds, query, selected_tags) do
    filter_sounds(sounds, query, selected_tags, :and)
  end

  def filter_sounds(sounds, query, selected_tags, tag_filter_mode) do
    sounds
    |> filter_by_tags(selected_tags, tag_filter_mode)
    |> filter_by_search(query)
  end

  defp filter_by_tags(sounds, [], _tag_filter_mode), do: sounds

  defp filter_by_tags(sounds, selected_tags, tag_filter_mode) do
    selected_tag_ids = MapSet.new(selected_tags, & &1.id)

    Enum.filter(sounds, fn sound ->
      sound_tag_ids = MapSet.new(sound.tags, & &1.id)

      case normalize_tag_filter_mode(tag_filter_mode) do
        :or -> not MapSet.disjoint?(selected_tag_ids, sound_tag_ids)
        :and -> MapSet.subset?(selected_tag_ids, sound_tag_ids)
      end
    end)
  end

  defp normalize_tag_filter_mode(mode) when mode in [:and, "and"], do: :and
  defp normalize_tag_filter_mode(mode) when mode in [:or, "or"], do: :or
  defp normalize_tag_filter_mode(_mode), do: :and

  defp filter_by_search(sounds, ""), do: sounds

  defp filter_by_search(sounds, query) do
    query = String.downcase(query)

    Enum.filter(sounds, fn sound ->
      filename_matches = String.downcase(sound.filename) =~ query

      tag_matches =
        Enum.any?(sound.tags, fn tag ->
          String.downcase(tag.name) =~ query
        end)

      filename_matches || tag_matches
    end)
  end
end
