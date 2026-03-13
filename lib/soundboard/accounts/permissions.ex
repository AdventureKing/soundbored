defmodule Soundboard.Accounts.Permissions do
  @moduledoc """
  Role-based permission checks for account actions.

  Discord role IDs are stored on users during OAuth and compared against
  configured role IDs per permission.
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
          user_roles: [String.t()],
          required_roles: [String.t()]
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
  def permission_decision(user, permission) when permission in [:upload_clips, :play_clips, :manage_settings] do
    required_roles = configured_role_ids(permission)
    user_roles = user_role_ids(user)

    cond do
      is_nil(user) ->
        decision(permission, false, :no_user, user_roles, required_roles)

      required_roles == [] and permission in [:upload_clips, :play_clips] ->
        decision(permission, true, :allowed_by_default, user_roles, required_roles)

      required_roles == [] and permission == :manage_settings ->
        decision(permission, false, :missing_required_role, user_roles, required_roles)

      Enum.any?(user_roles, &(&1 in required_roles)) ->
        decision(permission, true, :role_match, user_roles, required_roles)

      true ->
        decision(permission, false, :missing_required_role, user_roles, required_roles)
    end
  end

  @spec permission_decision(User.t() | nil, atom()) :: decision()
  def permission_decision(user, _permission) do
    decision(:upload_clips, false, :missing_required_role, user_role_ids(user), [])
  end

  @spec configured_role_ids(permission()) :: [String.t()]
  def configured_role_ids(:upload_clips) do
    :soundboard
    |> Application.get_env(:discord_upload_role_ids, [])
    |> normalize_role_ids()
  end

  def configured_role_ids(:play_clips) do
    :soundboard
    |> Application.get_env(:discord_play_role_ids, [])
    |> normalize_role_ids()
  end

  defp user_role_ids(%User{discord_roles: roles}), do: normalize_role_ids(roles)
  defp user_role_ids(%{discord_roles: roles}) when is_list(roles), do: normalize_role_ids(roles)
  defp user_role_ids(_), do: []

  defp normalize_role_ids(role_ids) when is_list(role_ids) do
    role_ids
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_role_ids(_), do: []

  def configured_role_ids(:manage_settings) do
    :soundboard
    |> Application.get_env(:discord_settings_admin_role_id)
    |> case do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> []
          role_id -> [role_id]
        end

      value when is_integer(value) ->
        [Integer.to_string(value)]

      _ ->
        []
    end
  end

  defp decision(permission, allowed?, reason, user_roles, required_roles) do
    %{
      permission: permission,
      allowed?: allowed?,
      reason: reason,
      user_roles: user_roles,
      required_roles: required_roles
    }
  end
end
