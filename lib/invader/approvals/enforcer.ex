defmodule Invader.Approvals.Enforcer do
  @moduledoc """
  Enforces human-in-the-loop approval for agent actions.

  When an action's scope is in the mission's `approval_scopes`,
  this module blocks execution until a human approves or denies
  via Telegram inline buttons.

  ## Flow

  1. Agent attempts action (e.g., `gh pr create`)
  2. Enforcer checks if scope requires approval
  3. If yes, creates PendingApproval record
  4. Sends Telegram message with APPROVE/DENY buttons
  5. Blocks on receive until button clicked or timeout
  6. Returns :approved, :denied, or :timeout

  ## Deterministic Guarantee

  This check happens at system level (ProxyController), not model level.
  The model cannot bypass or auto-approve.
  """

  alias Invader.Approvals.PendingApproval
  alias Invader.Connections.Connection
  alias Invader.Connections.Telegram.Client
  alias Invader.Missions.Mission

  require Logger

  @default_timeout :timer.minutes(5)

  @doc """
  Check if an action requires approval and wait for human decision.

  ## Parameters
    * `mission` - The mission attempting the action
    * `scope` - The scope string (e.g., "github:pr:create")
    * `action_type` - Type of action ("gh", "telegram", etc.)
    * `action_details` - Map with command details (args, etc.)
    * `opts` - Options:
      * `:timeout` - Max wait time in ms (default: 5 minutes)

  ## Returns
    * `:ok` - No approval required, proceed immediately
    * `{:approved, decided_by}` - Human approved the action
    * `{:denied, decided_by}` - Human denied the action
    * `{:error, :timeout}` - No decision within timeout
    * `{:error, :not_configured}` - Telegram not configured
    * `{:error, reason}` - Other error
  """
  @spec check_and_wait(Mission.t(), String.t(), String.t(), map(), keyword()) ::
          :ok
          | {:approved, String.t()}
          | {:denied, String.t()}
          | {:error, :timeout | :not_configured | term()}
  def check_and_wait(mission, scope, action_type, action_details, opts \\ []) do
    if requires_approval?(mission, scope) do
      wait_for_approval(mission, scope, action_type, action_details, opts)
    else
      :ok
    end
  end

  @doc """
  Check if a scope requires approval for a given mission.
  """
  @spec requires_approval?(Mission.t(), String.t()) :: boolean()
  def requires_approval?(mission, scope) do
    approval_scopes = mission.approval_scopes || []

    Enum.any?(approval_scopes, fn approval_scope ->
      scope_matches?(approval_scope, scope)
    end)
  end

  defp scope_matches?(pattern, scope) when pattern == scope, do: true

  defp scope_matches?(pattern, scope) do
    if String.ends_with?(pattern, ":*") do
      prefix = String.trim_trailing(pattern, "*")
      String.starts_with?(scope, prefix)
    else
      pattern == scope
    end
  end

  defp wait_for_approval(mission, scope, action_type, action_details, opts) do
    timeout = opts[:timeout] || @default_timeout

    case get_telegram_connection() do
      {:ok, %{telegram_bot_token: token, telegram_chat_id: chat_id}}
      when is_binary(token) and is_integer(chat_id) ->
        do_wait_for_approval(
          token,
          chat_id,
          mission,
          scope,
          action_type,
          action_details,
          timeout
        )

      {:ok, _} ->
        {:error, :not_configured}

      {:error, _} = error ->
        error
    end
  end

  defp do_wait_for_approval(token, chat_id, mission, scope, action_type, action_details, timeout) do
    timeout_at = DateTime.add(DateTime.utc_now(), timeout, :millisecond)
    callback_data = generate_callback_data()

    # Create pending approval record
    case PendingApproval.create(%{
           mission_id: mission.id,
           scope: scope,
           action_type: action_type,
           action_details: action_details,
           caller_pid: :erlang.term_to_binary(self()),
           callback_data: callback_data,
           timeout_at: timeout_at
         }) do
      {:ok, approval} ->
        # Send Telegram message with inline buttons
        case send_approval_request(
               token,
               chat_id,
               mission,
               scope,
               action_details,
               callback_data,
               timeout
             ) do
          {:ok, _message} ->
            # Block waiting for response
            receive do
              {:approval_decision, :approved, decided_by} ->
                {:approved, decided_by}

              {:approval_decision, :denied, decided_by} ->
                {:denied, decided_by}
            after
              timeout ->
                # Mark as timed out
                PendingApproval.timeout(approval)
                {:error, :timeout}
            end

          {:error, reason} ->
            # Clean up the approval record
            PendingApproval.destroy(approval)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to create pending approval: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp send_approval_request(
         token,
         chat_id,
         mission,
         scope,
         action_details,
         callback_data,
         timeout
       ) do
    # Load mission with sprite if needed
    mission =
      if Ash.Resource.loaded?(mission, :sprite) do
        mission
      else
        Ash.load!(mission, :sprite)
      end

    mission_name = (mission.sprite && mission.sprite.name) || "Unknown"
    timeout_minutes = div(timeout, 60_000)

    # Format action details
    args_text =
      case action_details do
        %{"args" => args} when is_list(args) ->
          Enum.join(args, " ")

        %{args: args} when is_list(args) ->
          Enum.join(args, " ")

        _ ->
          inspect(action_details)
      end

    message = """
    🔒 APPROVAL REQUIRED

    Mission: #{mission_name}
    Action: #{scope}
    Args: #{args_text}

    Expires in #{timeout_minutes} minutes
    """

    # Create inline keyboard with approve/deny buttons
    inline_keyboard = %{
      "inline_keyboard" => [
        [
          %{
            "text" => "✓ APPROVE",
            "callback_data" => "approve:#{callback_data}"
          },
          %{
            "text" => "✗ DENY",
            "callback_data" => "deny:#{callback_data}"
          }
        ]
      ]
    }

    Client.send_message(token, chat_id, message, reply_markup: inline_keyboard)
  end

  defp generate_callback_data do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp get_telegram_connection do
    Connection.get_by_type(:telegram)
  end

  @doc """
  Notify a waiting process of an approval decision.

  Called by the webhook handler when a user clicks an inline button.
  """
  @spec notify_decision(PendingApproval.t(), :approved | :denied, String.t()) ::
          :ok | {:error, term()}
  def notify_decision(
        %PendingApproval{caller_pid: caller_pid_binary} = approval,
        decision,
        decided_by
      )
      when is_binary(caller_pid_binary) do
    try do
      caller_pid = :erlang.binary_to_term(caller_pid_binary)

      # Update the approval record
      result =
        case decision do
          :approved -> PendingApproval.approve(approval, decided_by)
          :denied -> PendingApproval.deny(approval, decided_by)
        end

      case result do
        {:ok, _} ->
          # Notify the waiting process
          if Process.alive?(caller_pid) do
            send(caller_pid, {:approval_decision, decision, decided_by})
          end

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      ArgumentError ->
        Logger.warning("Invalid caller_pid binary in pending approval")
        {:error, :invalid_caller_pid}
    end
  end

  def notify_decision(_approval, _decision, _decided_by), do: {:error, :no_caller_pid}
end
