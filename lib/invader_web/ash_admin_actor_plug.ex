defmodule InvaderWeb.AshAdminActorPlug do
  @moduledoc """
  Actor plug for AshAdmin to use the current user as the actor.
  """
  @behaviour AshAdmin.ActorPlug

  @impl true
  def actor_assigns(socket, _session) do
    [actor: socket.assigns[:current_user]]
  end

  @impl true
  def set_actor_session(conn), do: conn
end
