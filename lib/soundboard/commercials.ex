defmodule Soundboard.Commercials do
  @moduledoc """
  Context for commercial clip management and settings.
  """

  require Logger

  import Ecto.Query

  alias Soundboard.Commercials.{Clip, Settings}
  alias Soundboard.Repo

  @allowed_extensions ~w(.mp3 .wav .ogg .m4a)
  @subdirectory "commercials"

  @doc """
  Returns the directory where commercial clips are stored.
  """
  @spec clips_dir() :: String.t()
  def clips_dir do
    Path.join(Soundboard.UploadsPath.dir(), @subdirectory)
  end

  @doc """
  Returns the full file path for a commercial clip filename.
  """
  @spec clip_file_path(String.t()) :: String.t()
  def clip_file_path(filename) do
    Path.join(clips_dir(), filename)
  end

  @doc """
  Returns current settings, or defaults if none have been saved yet.
  """
  @spec get_settings() :: Settings.t()
  def get_settings do
    case table_exists?("commercial_settings") do
      true -> Repo.one(from s in Settings, limit: 1) || %Settings{}
      false -> %Settings{}
    end
  end

  @doc """
  Saves (upserts) the commercial settings.
  """
  @spec save_settings(map()) :: {:ok, Settings.t()} | {:error, Ecto.Changeset.t()}
  def save_settings(attrs) do
    existing = Repo.one(from s in Settings, limit: 1) || %Settings{}

    existing
    |> Settings.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Returns all commercial clips ordered by name.
  """
  @spec list_clips() :: [Clip.t()]
  def list_clips do
    case table_exists?("commercial_clips") do
      true -> Repo.all(from c in Clip, order_by: [asc: c.name])
      false -> []
    end
  end

  @doc """
  Creates a commercial clip, copying the file to the commercials directory.
  """
  @spec create_clip(String.t(), String.t(), String.t()) ::
          {:ok, Clip.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def create_clip(name, src_path, original_filename) do
    with {:ok, ext} <- validate_extension(original_filename),
         filename <- build_filename(name, ext),
         :ok <- ensure_clips_dir(),
         dest_path <- clip_file_path(filename),
         :ok <- copy_file(src_path, dest_path) do
      case %Clip{} |> Clip.changeset(%{name: name, filename: filename}) |> Repo.insert() do
        {:ok, clip} ->
          {:ok, clip}

        {:error, changeset} ->
          File.rm(dest_path)
          {:error, changeset}
      end
    end
  end

  @doc """
  Deletes a commercial clip and its file.
  """
  @spec delete_clip(Clip.t()) :: {:ok, Clip.t()} | {:error, Ecto.Changeset.t()}
  def delete_clip(%Clip{} = clip) do
    case Repo.delete(clip) do
      {:ok, deleted} ->
        clip_file_path(clip.filename) |> File.rm()
        {:ok, deleted}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp validate_extension(filename) do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in @allowed_extensions do
      {:ok, ext}
    else
      {:error, "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."}
    end
  end

  defp build_filename(name, ext) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{base}_#{suffix}#{ext}"
  end

  defp ensure_clips_dir do
    case File.mkdir_p(clips_dir()) do
      :ok -> :ok
      {:error, reason} -> {:error, "Could not create directory: #{inspect(reason)}"}
    end
  end

  defp copy_file(src, dest) do
    case File.cp(src, dest) do
      :ok -> :ok
      {:error, reason} -> {:error, "Could not save file: #{inspect(reason)}"}
    end
  end

  defp table_exists?(table_name) do
    case Repo.__adapter__() do
      Ecto.Adapters.SQLite3 ->
        case Ecto.Adapters.SQL.query(
               Repo,
               "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
               [table_name]
             ) do
          {:ok, %{num_rows: n}} when n > 0 -> true
          _ -> false
        end

      _ ->
        true
    end
  rescue
    _ -> false
  end
end
