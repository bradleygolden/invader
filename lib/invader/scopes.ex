defmodule Invader.Scopes do
  @moduledoc """
  Domain for managing scopes and scope presets.
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Scopes.ScopePreset
  end
end
