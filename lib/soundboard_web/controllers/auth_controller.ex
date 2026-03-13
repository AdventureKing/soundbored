defmodule SoundboardWeb.AuthController do
  use SoundboardWeb, :controller
  require Logger

  plug Ueberauth

  alias Soundboard.Accounts.User
  alias Soundboard.Repo
  @discord_guilds_url "https://discord.com/api/users/@me/guilds"

  def request(conn, %{"provider" => "discord"} = _params) do
    conn
    |> put_session(:session_id, System.unique_integer())
    |> configure_session(renew: true)
  end

  def request(conn, _params) do
    conn
    |> put_status(:not_found)
    |> text("Unsupported auth provider")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    with :ok <- verify_discord_guild_membership(auth) do
      user_params = user_params_from_auth(auth)

      case find_or_create_user(user_params) do
        {:ok, user} ->
          conn
          |> put_session(:user_id, user.id)
          |> redirect(to: "/")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Error signing in")
          |> redirect(to: "/")
      end
    else
      {:error, {:not_in_required_guild, _guild_id} = reason} ->
        log_membership_failure(reason, auth.uid)

        conn
        |> redirect(to: ~p"/auth/denied/not-in-guild")

      {:error, reason} ->
        log_membership_failure(reason, auth.uid)

        conn
        |> put_flash(:error, membership_failure_message(reason))
        |> redirect(to: "/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate")
    |> redirect(to: "/")
  end

  def not_in_guild(conn, _params) do
    guild_id =
      case required_discord_guild_id() do
        {:ok, id} -> id
        :no_required_guild -> nil
      end

    conn
    |> put_layout(html: {SoundboardWeb.Layouts, :root})
    |> put_status(:forbidden)
    |> render(:not_in_guild, guild_id: guild_id, page_title: "Access denied")
  end

  defp verify_discord_guild_membership(auth) do
    case required_discord_guild_id() do
      {:ok, required_guild_id} ->
        with {:ok, guild_ids} <- guild_ids_for_membership_check(auth),
             true <- required_guild_id in guild_ids do
          :ok
        else
          false ->
            {:error, {:not_in_required_guild, required_guild_id}}

          {:error, reason} ->
            {:error, reason}
        end

      :no_required_guild ->
        :ok
    end
  end

  defp guild_ids_for_membership_check(auth) do
    case guild_ids_from_oauth_payload(auth) do
      {:ok, guild_ids} ->
        {:ok, guild_ids}

      :missing ->
        with {:ok, token} <- oauth_access_token(auth) do
          fetch_discord_guild_ids(token)
        end
    end
  end

  defp guild_ids_from_oauth_payload(auth) do
    guilds =
      auth
      |> Map.get(:extra)
      |> case do
        %{} = extra ->
          raw_info = Map.get(extra, :raw_info) || Map.get(extra, "raw_info")
          if is_map(raw_info), do: Map.get(raw_info, :guilds) || Map.get(raw_info, "guilds"), else: nil

        _ ->
          nil
      end

    if is_list(guilds) do
      guild_ids =
        guilds
        |> Enum.map(&guild_id_from_payload/1)
        |> Enum.filter(&is_binary/1)

      {:ok, guild_ids}
    else
      :missing
    end
  end

  defp required_discord_guild_id do
    case Application.get_env(:soundboard, :required_discord_guild_id) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: :no_required_guild, else: {:ok, trimmed}

      value when is_integer(value) ->
        {:ok, Integer.to_string(value)}

      _ ->
        :no_required_guild
    end
  end

  defp user_params_from_auth(auth) do
    user_params = %{
      discord_id: auth.uid,
      username: auth.info.nickname || auth.info.name,
      avatar: auth.info.image
    }

    user_params
  end

  defp oauth_access_token(%{credentials: credentials}) when not is_nil(credentials) do
    case Map.get(credentials, :token) do
      token when is_binary(token) and token != "" ->
        {:ok, token}

      token when is_binary(token) ->
        {:error, :missing_access_token}

      token when not is_nil(token) ->
        {:ok, to_string(token)}

      _ ->
        {:error, :missing_access_token}
    end
  end

  defp oauth_access_token(_), do: {:error, :missing_access_token}

  defp fetch_discord_guild_ids(token) do
    ensure_discord_http_started()

    headers = [
      {~c"Authorization", to_charlist("Bearer #{token}")},
      {~c"User-Agent", ~c"SoundboardOAuth"},
      {~c"Accept", ~c"application/json"}
    ]

    case :httpc.request(:get, {to_charlist(@discord_guilds_url), headers}, [], [body_format: :binary]) do
      {:ok, {{_status_line, status, _reason_phrase}, _headers, body}} when status in 200..299 ->
        with {:ok, decoded} <- Jason.decode(to_string(body)),
             true <- is_list(decoded),
             ids <- Enum.map(decoded, &guild_id_from_payload/1) do
          {:ok, Enum.filter(ids, &is_binary/1)}
        else
          _ ->
            {:error, :invalid_discord_response}
        end

      {:ok, {{_status_line, status, _reason_phrase}, _headers, body}} ->
        {:error, {:discord_api_error, status, to_string(body)}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp ensure_discord_http_started do
    _ = :inets.start()
    _ = :ssl.start()
    :ok
  end

  defp guild_id_from_payload(%{"id" => id}), do: to_string(id)
  defp guild_id_from_payload(%{id: id}), do: to_string(id)
  defp guild_id_from_payload(_), do: nil

  defp membership_failure_message(:missing_access_token),
    do: "Could not verify your Discord membership. Please try signing in again."

  defp membership_failure_message({:not_in_required_guild, guild_id}),
    do: "Access denied: you must be a member of Discord guild #{guild_id}."

  defp membership_failure_message({:discord_api_error, 429, _body}),
    do: "Discord is rate limiting membership checks. Please wait a moment and try again."

  defp membership_failure_message({:discord_api_error, _status, _body}),
    do: "Could not verify your Discord guild membership. Please try again."

  defp membership_failure_message({:http_error, _reason}),
    do: "Could not reach Discord membership check. Please try again."

  defp membership_failure_message(_other),
    do: "Error signing in"

  defp log_membership_failure(reason, discord_uid) do
    Logger.warning(
      "Discord OAuth membership check failed for user #{inspect(discord_uid)}: #{inspect(reason)}"
    )
  end

  defp find_or_create_user(%{discord_id: discord_id} = params) do
    case Repo.get_by(User, discord_id: discord_id) do
      nil ->
        %User{}
        |> User.changeset(params)
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/")
  end

  def debug_session(conn, _params) do
    json(conn, %{
      session: %{
        session_id: get_session(conn, :session_id),
        user_id: get_session(conn, :user_id)
      }
    })
  end
end
