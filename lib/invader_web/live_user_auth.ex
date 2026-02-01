defmodule InvaderWeb.LiveUserAuth do
  @moduledoc """
  LiveView authentication hooks for protecting routes.

  Used with `ash_authentication_live_session` which automatically
  loads the current_user from the session.
  """
  use InvaderWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_admin_required, _params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:halt, redirect(socket, to: ~p"/sign-in")}

      user.is_admin ->
        {:cont, socket}

      true ->
        {:halt, redirect(socket, to: ~p"/")}
    end
  end
end
