defmodule Invader.Saves do
  @moduledoc """
  Domain for managing sprite checkpoints/saves.
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Saves.Save
  end
end
