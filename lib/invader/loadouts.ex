defmodule Invader.Loadouts do
  @moduledoc """
  Domain for managing reusable prompt loadouts.
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Loadouts.Loadout
  end
end
