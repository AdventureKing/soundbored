defmodule Soundboard.Sounds.Uploads.Creator do
  @moduledoc false

  alias Soundboard.{PubSubTopics, Repo, Sound, Stats}
  alias Soundboard.Sounds.Tags
  alias Soundboard.Sounds.Uploads.Source

  @spec create(map(), map()) :: {:ok, Sound.t()} | {:error, term()}
  def create(params, source) do
    Repo.transaction(fn ->
      with {:ok, tags} <- Tags.resolve_many(params.tags),
           {:ok, sound} <- insert_sound(params, source, tags),
           sound <- Repo.preload(sound, [:tags, :user]) do
        sound
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, sound} ->
        broadcast_updates()
        {:ok, sound}

      {:error, reason} ->
        Source.cleanup_local_file(source.copied_file_path)
        {:error, reason}
    end
  end

  defp insert_sound(params, source, tags) do
    sound_attrs = %{
      filename: source.filename,
      source_type: source.source_type,
      url: source.url,
      user_id: params.user.id,
      volume: params.volume,
      duration_ms: source.duration_ms,
      tags: tags
    }

    %Sound{}
    |> Sound.changeset(sound_attrs)
    |> Repo.insert()
  end

  defp broadcast_updates do
    PubSubTopics.broadcast_files_updated(self())
    Stats.broadcast_stats_update()
  end
end
