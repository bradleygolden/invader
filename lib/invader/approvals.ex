defmodule Invader.Approvals do
  @moduledoc """
  Domain for managing human-in-the-loop action approvals.

  Provides deterministic approval enforcement for agent actions.
  When approval is required, the system blocks execution until
  a human approves or denies via Telegram.
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Approvals.PendingApproval
  end
end
