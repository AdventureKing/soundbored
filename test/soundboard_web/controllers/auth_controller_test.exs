defmodule SoundboardWeb.AuthControllerTest do
  use SoundboardWeb.ConnCase
  alias Soundboard.{Accounts.User, Repo}
  import ExUnit.CaptureLog
  import Mock

  setup %{conn: conn} do
    # Clean up users before each test
    Repo.delete_all(User)

    # Initialize session and CSRF token for all tests
    conn =
      conn
      |> init_test_session(%{})
      |> fetch_session()
      |> fetch_flash()

    # Mock Discord OAuth config for tests
    Application.put_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth,
      client_id: "test_client_id",
      client_secret: "test_client_secret"
    )

    Application.put_env(:soundboard, :required_discord_guild_id, "guild-1")

    on_exit(fn ->
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth)
      Application.delete_env(:soundboard, :required_discord_guild_id)
    end)

    {:ok, conn: conn}
  end

  describe "auth flow" do
    test "request/2 initiates Discord auth and sets session", %{conn: conn} do
      conn = get(conn, ~p"/auth/discord")

      # Redirect status
      assert conn.status == 302

      assert String.starts_with?(
               redirected_to(conn),
               "https://discord.com/api/oauth2/authorize"
             )
    end

    test "request/2 rejects unsupported providers with a controlled 404", %{conn: conn} do
      conn = get(conn, "/auth/not-real")

      assert response(conn, 404) == "Unsupported auth provider"
    end

    test "callback/2 creates new user on successful auth", %{conn: conn} do
      auth_data = %Ueberauth.Auth{
        uid: "12345",
        info: %Ueberauth.Auth.Info{
          nickname: "TestUser",
          image: "test_avatar.jpg"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "valid-token"
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{
            guilds: [%{"id" => "guild-1"}],
            member: %{"nick" => "GuildNick", "roles" => ["clip-uploader", "tester"]}
          }
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth_data)
        |> get(~p"/auth/discord/callback")

      assert redirected_to(conn) == "/"
      assert get_session(conn, :user_id)

      user = Repo.get_by(User, discord_id: "12345")
      assert user
      assert user.username == "GuildNick"
      assert user.avatar == "test_avatar.jpg"
      assert user.discord_roles == ["clip-uploader", "tester"]
    end

    test "callback/2 uses existing user if found", %{conn: conn} do
      # Get initial user count
      initial_count = Repo.aggregate(User, :count)

      # Create existing user
      {:ok, existing_user} =
        %User{}
        |> User.changeset(%{
          discord_id: "12345",
          username: "ExistingUser",
          avatar: "old_avatar.jpg",
          discord_roles: ["old-role"]
        })
        |> Repo.insert()

      auth_data = %{
        uid: "12345",
        info: %{
          nickname: "TestUser",
          image: "test_avatar.jpg"
        },
        credentials: %{
          token: "valid-token"
        },
        extra: %{
          raw_info: %{
            guilds: [%{"id" => "guild-1"}],
            member: %{"nick" => "GuildNickUpdated", "roles" => ["new-role", "tester"]}
          }
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth_data)
        |> get(~p"/auth/discord/callback")

      final_count = Repo.aggregate(User, :count)

      assert redirected_to(conn) == "/"
      assert get_session(conn, :user_id) == existing_user.id
      # Only increased by the one we created
      assert final_count == initial_count + 1

      refreshed_user = Repo.get!(User, existing_user.id)
      assert refreshed_user.username == "GuildNickUpdated"
      assert refreshed_user.avatar == "test_avatar.jpg"
      assert refreshed_user.discord_roles == ["new-role", "tester"]
    end

    test "callback/2 falls back to OAuth nickname when guild nickname is unavailable", %{
      conn: conn
    } do
      auth_data = %Ueberauth.Auth{
        uid: "fallback-user-1",
        info: %Ueberauth.Auth.Info{
          nickname: "OAuthNickname",
          image: "fallback_avatar.jpg"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "valid-token"
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{
            guilds: [%{"id" => "guild-1"}],
            member: %{"roles" => ["member"]}
          }
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth_data)
        |> get(~p"/auth/discord/callback")

      assert redirected_to(conn) == "/"
      user = Repo.get_by(User, discord_id: "fallback-user-1")
      assert user.username == "OAuthNickname"
    end

    test "callback/2 rejects users who are not in the required guild", %{conn: conn} do
      auth_data = %{
        uid: "67890",
        info: %{
          nickname: "TestUser",
          image: "test_avatar.jpg"
        },
        credentials: %{
          token: "valid-token"
        }
      }

      log =
        capture_log(fn ->
          with_mock :httpc,
            request: fn
              :get, _url, _headers, _options ->
                {:ok, {{~c"HTTP/1.1", 200, ~c"OK"}, [], ~c"[{\"id\":\"other-guild\"}]"}}
            end do
            conn =
              conn
              |> assign(:ueberauth_auth, auth_data)
              |> get(~p"/auth/discord/callback")

            assert redirected_to(conn) == "/auth/denied/not-in-guild"
          end
        end)

      assert log =~ "Discord OAuth membership check failed"
    end

    test "not_in_guild/2 shows a dedicated denied page", %{conn: conn} do
      conn = get(conn, ~p"/auth/denied/not-in-guild")

      response_body = html_response(conn, 403)

      assert response_body =~ "Access denied"
      assert response_body =~ "not in the required guild"
      refute response_body =~ "Required guild ID:"
    end

    test "callback/2 handles auth failures", %{conn: conn} do
      capture_log(fn ->
        conn =
          conn
          |> assign(:ueberauth_failure, %{
            errors: [
              %Ueberauth.Failure.Error{
                message_key: "invalid_credentials",
                message: "Invalid credentials"
              }
            ]
          })
          |> get(~p"/auth/discord/callback")

        assert redirected_to(conn) == "/"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed to authenticate"
      end)
    end

    test "logout/2 clears session and redirects", %{conn: conn} do
      conn =
        conn
        |> put_session(:user_id, "test_id")
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == "/"
      refute get_session(conn, :user_id)
    end

    test "debug_session/2 returns limited session info", %{conn: conn} do
      user = insert_user()

      conn =
        conn
        |> put_session(:session_id, 123)
        |> put_session(:user_id, user.id)
        |> get(~p"/debug/session")

      assert json = json_response(conn, 200)
      assert json == %{"session" => %{"session_id" => 123, "user_id" => user.id}}
    end
  end

  # Helper function
  defp insert_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer([:positive])}",
        discord_id: "#{System.unique_integer([:positive])}",
        avatar: "test_avatar.jpg"
      })
      |> Repo.insert()

    user
  end
end
