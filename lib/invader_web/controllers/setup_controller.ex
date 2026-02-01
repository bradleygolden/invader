defmodule InvaderWeb.SetupController do
  @moduledoc """
  Handles admin setup token validation.
  """
  use InvaderWeb, :controller

  def validate(conn, %{"token" => token}) do
    expected_token = Application.get_env(:invader, :admin_setup_token)

    if expected_token && token == expected_token do
      conn
      |> put_session(:admin_setup_validated, true)
      |> redirect(to: ~p"/sign-in")
    else
      conn
      |> put_flash(:error, "Invalid setup token")
      |> redirect(to: ~p"/sign-in")
    end
  end
end
