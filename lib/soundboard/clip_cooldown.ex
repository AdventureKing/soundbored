defmodule Soundboard.ClipCooldown do
  @moduledoc """
  Enforces per-clip playback cooldowns.
  """

  import Ecto.Query

  alias Soundboard.{Repo, Sound}
  alias Soundboard.Stats.Play

  @type cooldown_details :: %{
          cooldown_seconds: pos_integer(),
          remaining_seconds: pos_integer(),
          last_played_at: NaiveDateTime.t()
        }

  @spec check(Sound.t() | String.t()) :: :ok | {:error, cooldown_details()}
  def check(%Sound{id: sound_id, internal_cooldown_seconds: cooldown_seconds})
      when is_integer(sound_id) and is_integer(cooldown_seconds) and cooldown_seconds > 0 do
    enforce_cooldown(sound_id, cooldown_seconds)
  end

  def check(%Sound{}), do: :ok

  def check(sound_name) when is_binary(sound_name) do
    case Repo.get_by(Sound, filename: sound_name) do
      %Sound{} = sound -> check(sound)
      _ -> :ok
    end
  end

  def check(_), do: :ok

  @spec message(cooldown_details()) :: String.t()
  def message(%{remaining_seconds: remaining_seconds}) do
    "That clip is on cooldown. Try again in #{format_seconds(remaining_seconds)}."
  end

  defp enforce_cooldown(sound_id, cooldown_seconds) do
    case most_recent_played_at(sound_id) do
      %NaiveDateTime{} = last_played_at ->
        elapsed_seconds =
          max(NaiveDateTime.diff(NaiveDateTime.utc_now(), last_played_at, :second), 0)

        remaining_seconds = cooldown_seconds - elapsed_seconds

        if remaining_seconds > 0 do
          {:error,
           %{
             cooldown_seconds: cooldown_seconds,
             remaining_seconds: remaining_seconds,
             last_played_at: last_played_at
           }}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp most_recent_played_at(sound_id) do
    from(p in Play, where: p.sound_id == ^sound_id, select: max(p.inserted_at))
    |> Repo.one()
  end

  defp format_seconds(total_seconds) when is_integer(total_seconds) and total_seconds > 0 do
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    cond do
      minutes > 0 and seconds > 0 -> "#{minutes}m #{seconds}s"
      minutes > 0 -> "#{minutes}m"
      true -> "#{seconds}s"
    end
  end

  defp format_seconds(_), do: "0s"
end
