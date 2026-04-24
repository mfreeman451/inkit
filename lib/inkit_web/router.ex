defmodule InkitWeb.Router do
  use InkitWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InkitWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json", "multipart"]
    plug InkitWeb.Plugs.ApiLogPlug
  end

  scope "/", InkitWeb do
    pipe_through :browser

    live "/", VisualAssistantLive, :index
  end

  scope "/", InkitWeb do
    pipe_through [:browser, InkitWeb.Plugs.ApiLogPlug]

    get "/images/:image_id", VisualAssistantController, :image
  end

  scope "/", InkitWeb do
    pipe_through :api

    post "/upload", VisualAssistantController, :upload
    post "/chat/:image_id", VisualAssistantController, :chat
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:inkit, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: InkitWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
