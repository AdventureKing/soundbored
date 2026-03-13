defmodule SoundboardWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :soundboard
  use Plug.ErrorHandler

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_soundboard_key",
    signing_salt: "dxNUerVp",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :soundboard,
    gzip: false,
    only: SoundboardWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :soundboard
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: 30_000_000,
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SoundboardWeb.Router

  @impl true
  def handle_errors(conn, %{reason: %OAuth2.Error{} = reason}) do
    if conn.request_path == "/auth/discord/callback" do
      message =
        case reason.body do
          %{"error_description" => description}
          when is_binary(description) and String.contains?(description, "rate limited") ->
            "Discord sign-in is being rate limited right now. Please wait a moment and try again."

          _ ->
            "Discord sign-in failed. Please try again."
        end

      conn
      |> Plug.Conn.put_status(:found)
      |> Phoenix.Controller.put_flash(:error, message)
      |> Phoenix.Controller.redirect(to: "/")
      |> Plug.Conn.halt()
    else
      status = if is_nil(conn.status), do: 500, else: conn.status
      Plug.Conn.send_resp(conn, status, "Something went wrong.")
    end
  end

  def handle_errors(conn, _params) do
    status = if is_nil(conn.status), do: 500, else: conn.status
    send_resp(conn, status, "Something went wrong.")
  end
end
