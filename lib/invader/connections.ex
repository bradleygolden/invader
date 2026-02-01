defmodule Invader.Connections do
  @moduledoc """
  Domain for managing external service connections (GitHub, Linear, etc.).
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Connections.Connection
    resource Invader.Connections.Request
  end
end
