defmodule InkitWeb.PageController do
  use InkitWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
