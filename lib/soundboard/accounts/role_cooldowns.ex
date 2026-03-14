defmodule Soundboard.Accounts.RoleCooldowns do
  @moduledoc """
  Role cooldown configuration and effective cooldown helpers.
  """

  require Logger

  import Ecto.Query

  alias Soundboard.Accounts.{RoleCooldown, User}
  alias Ecto.Adapters.SQL
  alias Soundboard.Repo

  @default_cooldown_seconds 600

  @type cooldown_map :: %{optional(String.t()) => pos_integer()}
  @type replace_error :: {:invalid_cooldown, String.t()}

  @spec default_cooldown_seconds() :: pos_integer()
  def default_cooldown_seconds do
    case Application.get_env(
           :soundboard,
           :default_playback_cooldown_seconds,
           @default_cooldown_seconds
         ) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_cooldown_seconds
    end
  end

  @spec list() :: [RoleCooldown.t()]
  def list do
    if role_cooldowns_table_exists?() do
      from(rc in RoleCooldown, order_by: [asc: rc.role_id])
      |> Repo.all()
    else
      []
    end
  end

  @spec cooldown_by_role_id() :: cooldown_map()
  def cooldown_by_role_id do
    list()
    |> Map.new(fn %RoleCooldown{role_id: role_id, cooldown_seconds: cooldown_seconds} ->
      {role_id, cooldown_seconds}
    end)
  end

  @spec effective_cooldown_seconds(User.t() | %{discord_roles: [term()]} | [term()] | nil) ::
          pos_integer() | nil
  def effective_cooldown_seconds(%User{discord_roles: role_ids}) do
    effective_cooldown_seconds(role_ids)
  end

  def effective_cooldown_seconds(%{discord_roles: role_ids}) when is_list(role_ids) do
    effective_cooldown_seconds(role_ids)
  end

  def effective_cooldown_seconds(role_ids) when is_list(role_ids) do
    default_cooldown_seconds = default_cooldown_seconds()
    cooldowns = cooldown_by_role_id()

    role_ids
    |> normalize_role_ids()
    |> case do
      [] ->
        [default_cooldown_seconds]

      normalized_role_ids ->
        Enum.map(normalized_role_ids, &Map.get(cooldowns, &1, default_cooldown_seconds))
    end
    |> case do
      values -> Enum.min(values)
    end
  end

  def effective_cooldown_seconds(_), do: nil

  @spec replace_for_roles([term()], map()) :: :ok | {:error, replace_error()}
  def replace_for_roles(role_ids, cooldown_inputs)
      when is_list(role_ids) and is_map(cooldown_inputs) do
    unless role_cooldowns_table_exists?() do
      {:error, {:invalid_cooldown, "Role cooldowns table is missing. Run database migrations."}}
    else
      normalized_role_ids = normalize_role_ids(role_ids)

      Repo.transaction(fn ->
        existing =
          from(rc in RoleCooldown, where: rc.role_id in ^normalized_role_ids)
          |> Repo.all()
          |> Map.new(&{&1.role_id, &1})

        Enum.each(normalized_role_ids, fn role_id ->
          case parse_cooldown_input(Map.get(cooldown_inputs, role_id)) do
            {:ok, cooldown_seconds} ->
              upsert_role_cooldown(existing[role_id], role_id, cooldown_seconds)

            :clear ->
              maybe_delete(existing[role_id])

            {:error, message} ->
              Repo.rollback({:invalid_cooldown, message})
          end
        end)
      end)
      |> case do
        {:ok, _} -> :ok
        {:error, {:invalid_cooldown, _} = reason} -> {:error, reason}
        {:error, reason} -> {:error, {:invalid_cooldown, inspect(reason)}}
      end
    end
  end

  def replace_for_roles(_role_ids, _cooldown_inputs),
    do: {:error, {:invalid_cooldown, "Cooldown inputs are invalid"}}

  defp upsert_role_cooldown(nil, role_id, cooldown_seconds) do
    %RoleCooldown{}
    |> RoleCooldown.changeset(%{role_id: role_id, cooldown_seconds: cooldown_seconds})
    |> Repo.insert!()
  end

  defp upsert_role_cooldown(%RoleCooldown{} = existing, role_id, cooldown_seconds) do
    existing
    |> RoleCooldown.changeset(%{role_id: role_id, cooldown_seconds: cooldown_seconds})
    |> Repo.update!()
  end

  defp maybe_delete(nil), do: :ok
  defp maybe_delete(%RoleCooldown{} = role_cooldown), do: Repo.delete!(role_cooldown)

  defp parse_cooldown_input(nil), do: :clear

  defp parse_cooldown_input(value) when is_binary(value) do
    value
    |> String.trim()
    |> parse_trimmed_cooldown()
  end

  defp parse_cooldown_input(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp parse_cooldown_input(value) when is_integer(value), do: :clear
  defp parse_cooldown_input(_), do: {:error, "Cooldown must be a positive integer or blank"}

  defp parse_trimmed_cooldown(""), do: :clear

  defp parse_trimmed_cooldown(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 ->
        {:ok, parsed}

      {parsed, ""} when parsed <= 0 ->
        :clear

      _ ->
        {:error, "Cooldown must be a positive integer or blank"}
    end
  end

  defp normalize_role_ids(role_ids) do
    role_ids
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp role_cooldowns_table_exists? do
    case Repo.__adapter__() do
      Ecto.Adapters.SQLite3 ->
        case SQL.query(
               Repo,
               "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'role_cooldowns' LIMIT 1",
               []
             ) do
          {:ok, %{num_rows: num_rows}} when num_rows > 0 ->
            true

          {:ok, _} ->
            false

          {:error, reason} ->
            Logger.warning("Could not check role_cooldowns table in SQLite: #{inspect(reason)}")
            false
        end

      _other_adapter ->
        # For non-SQLite adapters in tests or future deployments, keep prior behavior.
        true
    end
  rescue
    error ->
      Logger.warning("Role cooldown table check failed: #{inspect(error)}")
      false
  end
end
