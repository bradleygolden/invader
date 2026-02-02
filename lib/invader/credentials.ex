defmodule Invader.Credentials do
  @moduledoc """
  Domain for managing saved API credentials with encryption.
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Credentials.SavedCredential
  end
end
