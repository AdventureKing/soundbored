defmodule Soundboard.Sounds.Uploads.Normalizer do
  @moduledoc false

  import Ecto.Changeset

  alias Soundboard.{Sound, Volume}
  alias Soundboard.Sounds.Uploads.CreateRequest

  @spec normalize(CreateRequest.t()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def normalize(%CreateRequest{} = request) do
    case request.user do
      %Soundboard.Accounts.User{} = user ->
        source_type = normalize_source_type(request.source_type, request.upload, request.url)
        name = normalize_name(request.name)

        build_normalized_params(%{
          user: user,
          source_type: source_type,
          name: name,
          url: normalize_url(request.url),
          tags: request.tags,
          volume: request.volume,
          is_join_sound: request.is_join_sound,
          is_leave_sound: request.is_leave_sound,
          default_volume_percent: request.default_volume_percent || 100,
          upload: request.upload
        })

      _ ->
        {:error, add_error(change(%Sound{}), :user_id, "can't be blank")}
    end
  end

  defp build_normalized_params(%{
         user: %Soundboard.Accounts.User{} = user,
         source_type: source_type,
         name: name,
         url: url,
         tags: tags,
         volume: volume,
         is_join_sound: is_join_sound,
         is_leave_sound: is_leave_sound,
         default_volume_percent: default_volume_percent,
         upload: upload
       }) do
    normalized_tags = normalize_tags(tags)

    cond do
      blank?(name) ->
        {:error, add_error(change(%Sound{}), :filename, "can't be blank")}

      normalized_tags == [] ->
        {:error, add_error(change(%Sound{}), :tags, "must include at least one tag")}

      true ->
        {:ok,
         %{
           user: user,
           source_type: source_type,
           name: name,
           url: url,
           tags: normalized_tags,
           volume:
             Volume.percent_to_decimal(volume, normalize_default_volume(default_volume_percent)),
           is_join_sound: to_boolean(is_join_sound),
           is_leave_sound: to_boolean(is_leave_sound),
           upload: upload
         }}
    end
  end

  defp build_normalized_params(_params) do
    {:error, add_error(change(%Sound{}), :user_id, "can't be blank")}
  end

  defp normalize_default_volume(value), do: Volume.normalize_percent(value, 100)

  defp normalize_tags(nil), do: []

  defp normalize_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> Enum.map(&normalize_tag_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&normalize_tag_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tags(_), do: []

  defp normalize_tag_item(%Soundboard.Tag{} = tag), do: tag

  defp normalize_tag_item(%{id: _} = tag), do: tag
  defp normalize_tag_item(%{"id" => _} = tag), do: tag

  defp normalize_tag_item(%{name: name}) when is_binary(name), do: normalize_tag_item(name)
  defp normalize_tag_item(%{"name" => name}) when is_binary(name), do: normalize_tag_item(name)

  defp normalize_tag_item(tag) when is_binary(tag) do
    case tag |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_tag_item(_), do: nil

  defp normalize_source_type(source_type, upload, url) when is_binary(source_type) do
    case source_type |> String.trim() |> String.downcase() do
      "local" -> "local"
      "url" -> "url"
      _ -> infer_source_type(upload, url)
    end
  end

  defp normalize_source_type(_source_type, upload, url), do: infer_source_type(upload, url)

  defp infer_source_type(upload, url) do
    cond do
      is_map(upload) -> "local"
      is_binary(url) and String.trim(url) != "" -> "url"
      true -> "local"
    end
  end

  defp normalize_name(name) when is_binary(name), do: String.trim(name)
  defp normalize_name(_), do: nil

  defp normalize_url(url) when is_binary(url), do: String.trim(url)
  defp normalize_url(_), do: nil

  defp to_boolean(value) when value in [true, "true", "1", 1, "on", "yes"], do: true
  defp to_boolean(_), do: false

  defp blank?(value), do: value in [nil, ""]
end
