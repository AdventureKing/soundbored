defmodule Soundboard.Accounts.Permissions do
  @moduledoc """
  Discord permission checks for account actions.

  Discord role IDs are stored on users during OAuth and compared against
  configured role IDs for upload/play permissions.

  Settings access is controlled via configured Discord user IDs.
  """

  alias Soundboard.Accounts.User

  @type permission :: :upload_clips | :play_clips | :manage_settings
  @type decision_reason ::
          :allowed_by_default
          | :role_match
          | :no_user
          | :missing_required_role

  @type decision :: %{
          permission: permission(),
          allowed?: boolean(),
          reason: decision_reason(),
          user_ids: [String.t()],
          required_ids: [String.t()]
        }

  @spec can?(User.t() | nil, permission()) :: boolean()
  def can?(user, permission) do
    permission_decision(user, permission).allowed?
  end

  @spec can_upload_clips?(User.t() | nil) :: boolean()
  def can_upload_clips?(user), do: can?(user, :upload_clips)

  @spec can_play_clips?(User.t() | nil) :: boolean()
  def can_play_clips?(user), do: can?(user, :play_clips)

  @spec can_manage_settings?(User.t() | nil) :: boolean()
  def can_manage_settings?(user), do: can?(user, :manage_settings)

  @spec permission_decision(User.t() | nil, permission()) :: decision()
  def permission_decision(user, permission)
      when permission in [:upload_clips, :play_clips, :manage_settings] do
    required_ids = configured_required_ids(permission)
    user_ids = user_ids_for_permission(user, permission)

    cond do
      is_nil(user) ->
        decision(permission, false, :no_user, user_ids, required_ids)

      required_ids == [] and permission in [:upload_clips, :play_clips] ->
        decision(permission, true, :allowed_by_default, user_ids, required_ids)

      required_ids == [] and permission == :manage_settings ->
        decision(
          permission,
          settings_allowed_by_default?(user),
          default_settings_reason(user),
          user_ids,
          required_ids
        )

      Enum.any?(user_ids, &(&1 in required_ids)) ->
        decision(permission, true, :role_match, user_ids, required_ids)

      true ->
        decision(permission, false, :missing_required_role, user_ids, required_ids)
    end
  end

  @spec permission_decision(User.t() | nil, atom()) :: decision()
  def permission_decision(user, _permission) do
    decision(:upload_clips, false, :missing_required_role, user_role_ids(user), [])
  end

  @spec configured_required_ids(permission()) :: [String.t()]
  def configured_required_ids(:upload_clips) do
    :soundboard
    |> Application.get_env(:discord_upload_role_ids, [])
    |> normalize_discord_ids()
  end

  def configured_required_ids(:play_clips) do
    :soundboard
    |> Application.get_env(:discord_play_role_ids, [])
    |> normalize_discord_ids()
  end

  def configured_required_ids(:manage_settings) do
    :soundboard
    |> Application.get_env(:discord_settings_admin_user_ids, [])
    |> normalize_discord_ids()
  end

  defp user_ids_for_permission(user, :manage_settings), do: user_discord_id(user)
  defp user_ids_for_permission(user, _permission), do: user_role_ids(user)

  defp user_role_ids(%User{discord_roles: roles}), do: normalize_discord_ids(roles)

  defp user_role_ids(%{discord_roles: roles}) when is_list(roles),
    do: normalize_discord_ids(roles)

  defp user_role_ids(_), do: []

  defp user_discord_id(%User{discord_id: discord_id}), do: normalize_discord_ids(discord_id)
  defp user_discord_id(%{discord_id: discord_id}), do: normalize_discord_ids(discord_id)
  defp user_discord_id(_), do: []

  defp settings_allowed_by_default?(nil), do: false

  defp settings_allowed_by_default?(_user) do
    Application.get_env(:soundboard, :env) == :test
  end

  defp default_settings_reason(user) do
    if settings_allowed_by_default?(user), do: :allowed_by_default, else: :missing_required_role
  end

  defp normalize_discord_ids(discord_ids) when is_list(discord_ids) do
    discord_ids
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_discord_ids(discord_ids) when is_binary(discord_ids) do
    discord_ids
    |> String.split(",", trim: true)
    |> normalize_discord_ids()
  end

  defp normalize_discord_ids(discord_ids) when is_integer(discord_ids),
    do: [Integer.to_string(discord_ids)]

  defp normalize_discord_ids(_), do: []

  defp decision(permission, allowed?, reason, user_ids, required_ids) do
    %{
      permission: permission,
      allowed?: allowed?,
      reason: reason,
      user_ids: user_ids,
      required_ids: required_ids
    }
  end
end
