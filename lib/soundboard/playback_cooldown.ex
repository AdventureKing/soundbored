defmodule Soundboard.PlaybackCooldown do
  @moduledoc """
  Enforces per-user playback cooldowns derived from Discord role IDs.
  """

  import Ecto.Query

  alias Soundboard.Accounts.{RoleCooldowns, User}
  alias Soundboard.Repo
  alias Soundboard.Stats.Play

  @type cooldown_details :: %{
          cooldown_seconds: pos_integer(),
          remaining_seconds: pos_integer(),
          last_played_at: NaiveDateTime.t()
        }

  @spec active_cooldown_end_unix_ms(User.t() | nil) :: integer() | nil
  def active_cooldown_end_unix_ms(%User{id: user_id} = user) when is_integer(user_id) do
    with cooldown_seconds when is_integer(cooldown_seconds) and cooldown_seconds > 0 <-
           RoleCooldowns.effective_cooldown_seconds(user),
         %NaiveDateTime{} = last_played_at <- most_recent_played_at(user_id) do
      ends_at_ms =
        last_played_at
        |> NaiveDateTime.add(cooldown_seconds, :second)
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix(:millisecond)

      if ends_at_ms > System.system_time(:millisecond), do: ends_at_ms, else: nil
    else
      _ -> nil
    end
  end

  def active_cooldown_end_unix_ms(_), do: nil

  @spec check(User.t() | nil) :: :ok | {:error, cooldown_details()}
  def check(%User{id: user_id} = user) when is_integer(user_id) do
    case RoleCooldowns.effective_cooldown_seconds(user) do
      cooldown_seconds when is_integer(cooldown_seconds) and cooldown_seconds > 0 ->
        enforce_cooldown(user_id, cooldown_seconds)

      _ ->
        :ok
    end
  end

  def check(_), do: :ok

  @spec message(cooldown_details()) :: String.t()
  def message(%{remaining_seconds: remaining_seconds}) do
    "You are on cooldown. Try again in #{format_seconds(remaining_seconds)}."
  end

  @spec enforce_cooldown(integer(), pos_integer()) :: :ok | {:error, cooldown_details()}
  defp enforce_cooldown(user_id, cooldown_seconds) do
    case most_recent_played_at(user_id) do
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

  defp most_recent_played_at(user_id) do
    from(p in Play, where: p.user_id == ^user_id, select: max(p.inserted_at))
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
