defmodule Invader.Missions do
  @moduledoc """
  Domain for managing missions and waves.
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Missions.Mission
    resource Invader.Missions.Wave
    resource Invader.Missions.GithubRepo
  end
end
