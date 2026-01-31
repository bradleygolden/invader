defmodule InvaderWeb.Router do
  use InvaderWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InvaderWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", InvaderWeb do
    pipe_through :browser

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
  end

  # Other scopes may use custom stacks.
  # scope "/api", InvaderWeb do
  #   pipe_through :api
  # end

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
