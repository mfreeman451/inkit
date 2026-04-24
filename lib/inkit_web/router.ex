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
    plug :put_secure_browser_headers
    plug InkitWeb.Plugs.ApiLogPlug
  end

  pipeline :rate_limit_upload do
    plug InkitWeb.Plugs.RateLimit, bucket: :upload
  end

  pipeline :rate_limit_chat do
    plug InkitWeb.Plugs.RateLimit, bucket: :chat
  end

  pipeline :rate_limit_chat_stream do
    plug InkitWeb.Plugs.RateLimit, bucket: :chat_stream
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
    pipe_through [:api, :rate_limit_upload]
    post "/upload", VisualAssistantController, :upload
  end

  scope "/", InkitWeb do
    pipe_through [:api, :rate_limit_chat]
    post "/chat/:image_id", VisualAssistantController, :chat
  end

  scope "/", InkitWeb do
    pipe_through [:api, :rate_limit_chat_stream]
    post "/chat/:image_id/stream", VisualAssistantController, :stream_chat
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
