defmodule InvaderWeb.Router do
  use InvaderWeb, :router
  use AshAuthentication.Phoenix.Router
  import AshAdmin.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InvaderWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes - sign in page
  scope "/", InvaderWeb do
    pipe_through :browser

    # Admin setup routes - must be before auth_routes to avoid being shadowed
    get "/auth/setup/validate", SetupController, :validate
    post "/auth/setup/create-admin", SetupController, :create_admin

    sign_in_route(
      auth_routes_prefix: "/auth",
      live_view: InvaderWeb.SignInLive,
      on_mount_prepend: [{InvaderWeb.LiveUserAuth, :redirect_if_authenticated}]
    )

    sign_out_route AuthController

    # Magic link sign-in route (must be before auth_routes)
    magic_sign_in_route(
      Invader.Accounts.User,
      :magic_link,
      auth_routes_prefix: "/auth",
      path: "/auth/user/magic_link"
    )

    auth_routes AuthController, Invader.Accounts.User, path: "/auth"
  end

  # Protected routes - require authentication
  scope "/", InvaderWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated,
      on_mount: {InvaderWeb.LiveUserAuth, :live_user_required} do
      live "/", DashboardLive, :index
      live "/dashboard", DashboardLive, :index

      # Sprite modal routes
      live "/sprites/new", DashboardLive, :new_sprite
      live "/sprites/:id", DashboardLive, :show_sprite
      live "/sprites/:id/edit", DashboardLive, :edit_sprite

      # Mission modal routes
      live "/missions/new", DashboardLive, :new_mission
      live "/missions/:id", DashboardLive, :show_mission
      live "/missions/:id/edit", DashboardLive, :edit_mission

      # Settings modal route
      live "/settings", DashboardLive, :settings

      # Loadouts modal route
      live "/loadouts", DashboardLive, :loadouts

      # Connections modal route
      live "/connections", DashboardLive, :connections
    end
  end

  # Admin routes - require admin authentication
  scope "/" do
    pipe_through :browser

    ash_admin "/admin",
              AshAuthentication.Phoenix.LiveSession.opts(
                on_mount: [{InvaderWeb.LiveUserAuth, :live_admin_required}]
              )
  end

  # API routes for CLI proxy
  scope "/api", InvaderWeb do
    pipe_through :api

    post "/proxy", ProxyController, :run
  end

  # CLI scripts (served as static files)
  scope "/cli", InvaderWeb do
    pipe_through :api

    get "/invader.sh", CliController, :invader_script
    get "/install.sh", CliController, :install_script
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:invader, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: InvaderWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
