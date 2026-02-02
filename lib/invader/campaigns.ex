defmodule Invader.Campaigns do
  @moduledoc """
  Domain for managing campaigns - orchestrated sequences of missions as directed graphs.

  Campaigns compose missions and allow:
  - Parallel execution of multiple mission branches
  - Full loops with cycle detection
  - Defined start points
  - Visual node-graph editing
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Campaigns.Campaign
    resource Invader.Campaigns.CampaignNode
    resource Invader.Campaigns.CampaignEdge
    resource Invader.Campaigns.CampaignRun
    resource Invader.Campaigns.CampaignNodeExecution
  end
end
