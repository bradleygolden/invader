defmodule InvaderWeb.AuthController do
  use InvaderWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, _token) do
    conn
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: ~p"/")
  end

  def failure(conn, _activity, reason) do
    message =
      case reason do
        %Ash.Error.Invalid{errors: errors} ->
          errors
          |> Enum.map(fn
            %Ash.Error.Changes.InvalidAttribute{message: msg} -> msg
            error -> Exception.message(error)
          end)
          |> Enum.join(", ")

        _ ->
          "Authentication failed"
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    conn
    |> clear_session(:invader)
    |> put_flash(:info, "Signed out successfully")
    |> redirect(to: ~p"/sign-in")
  end
end
