defmodule InvaderWeb.AuthController do
  use InvaderWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, _token) do
    conn
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: ~p"/")
  end

  def failure(conn, activity, reason) do
    require Logger
    Logger.error("OAuth failure - activity: #{inspect(activity)}, reason: #{inspect(reason)}")

    message =
      case reason do
        %Ash.Error.Invalid{errors: errors} ->
          errors
          |> Enum.map(fn
            %Ash.Error.Changes.InvalidAttribute{message: msg} -> msg
            error -> Exception.message(error)
          end)
          |> Enum.join(", ")

        %Ash.Error.Forbidden{errors: errors} ->
          errors
          |> Enum.map(&Exception.message/1)
          |> Enum.join(", ")

        _ ->
          Exception.message(reason)
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
