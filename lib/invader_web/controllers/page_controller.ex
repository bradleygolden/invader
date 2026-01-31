defmodule InvaderWeb.PageController do
  use InvaderWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
