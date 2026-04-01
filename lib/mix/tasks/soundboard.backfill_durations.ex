defmodule Mix.Tasks.Soundboard.BackfillDurations do
  @shortdoc "Backfills sounds.duration_ms for existing clips"
  @moduledoc """
  Backfills `sounds.duration_ms` for rows where it is currently `NULL`.

  By default, this task probes local files only.

      mix soundboard.backfill_durations

  Options:

    * `--limit N` - Process at most `N` sounds.
    * `--dry-run` - Probe and report without writing changes.
    * `--include-url` - Also probe URL-backed sounds.
  """

  use Mix.Task
  import Ecto.Query

  alias Soundboard.Media.Duration
  alias Soundboard.{Repo, Sound, UploadsPath}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [limit: :integer, dry_run: :boolean, include_url: :boolean]
      )

    dry_run? = Keyword.get(opts, :dry_run, false)
    include_url? = Keyword.get(opts, :include_url, false)
    limit = Keyword.get(opts, :limit)

    pending = fetch_pending_sounds(limit)

    Mix.shell().info("Found #{length(pending)} sound(s) with NULL duration_ms")

    {updated, skipped, failed} =
      Enum.reduce(pending, {0, 0, 0}, fn sound, {updated_acc, skipped_acc, failed_acc} ->
        case probe_duration(sound, include_url?) do
          {:ok, duration_ms} ->
            maybe_persist_duration(sound.id, duration_ms, dry_run?)
            {updated_acc + 1, skipped_acc, failed_acc}

          :skip ->
            {updated_acc, skipped_acc + 1, failed_acc}

          {:error, _reason} ->
            {updated_acc, skipped_acc, failed_acc + 1}
        end
      end)

    action = if dry_run?, do: "would update", else: "updated"

    Mix.shell().info(
      "Backfill finished: #{action}=#{updated} skipped=#{skipped} failed=#{failed} total=#{length(pending)}"
    )
  end

  defp fetch_pending_sounds(limit) do
    base_query =
      from(s in Sound,
        where: is_nil(s.duration_ms),
        order_by: [asc: s.id]
      )

    query =
      case limit do
        value when is_integer(value) and value > 0 -> from(s in base_query, limit: ^value)
        _ -> base_query
      end

    Repo.all(query)
  end

  defp maybe_persist_duration(_sound_id, _duration_ms, true), do: :ok

  defp maybe_persist_duration(sound_id, duration_ms, false) do
    from(s in Sound, where: s.id == ^sound_id)
    |> Repo.update_all(set: [duration_ms: duration_ms])

    :ok
  end

  defp probe_duration(%Sound{source_type: "local", filename: filename}, _include_url?) do
    local_path = UploadsPath.file_path(filename)

    if File.exists?(local_path) do
      Duration.probe_local(local_path)
    else
      {:error, :local_file_missing}
    end
  end

  defp probe_duration(%Sound{source_type: "url", url: url}, true) when is_binary(url) do
    Duration.probe_url(url)
  end

  defp probe_duration(%Sound{source_type: "url"}, false), do: :skip
  defp probe_duration(%Sound{source_type: nil}, _include_url?), do: :skip
  defp probe_duration(%Sound{}, _include_url?), do: :skip
end
