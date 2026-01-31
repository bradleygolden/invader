defmodule Invader.Sprites do
  @moduledoc """
  Domain for managing sprite.dev environments.
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Sprites.Sprite
  end
end
