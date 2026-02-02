defmodule Invader.Workers.CampaignNodeRunner do
  @moduledoc """
  Oban worker that executes individual workflow nodes.

  Routes to the appropriate executor based on node type:
  - mission: Creates and monitors a Mission
  - conditional: Evaluates condition, returns branch taken
  - delay: Schedules continuation after delay
  - loop: Manages iteration counter and condition
  """
  use Oban.Worker, queue: :workflows, max_attempts: 3

  alias Invader.Campaigns.{CampaignOrchestrator, CampaignNodeExecution}

  alias Invader.Campaigns.Executors.{
    MissionExecutor,
    ConditionalExecutor,
    DelayExecutor,
    LoopExecutor
  }

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "run_id" => run_id,
      "node_id" => node_id,
      "execution_id" => execution_id,
      "node_type" => node_type,
      "config" => config,
      "context" => context
    } = args

    # Mark execution as started
    case CampaignNodeExecution.get(execution_id) do
      {:ok, execution} ->
        {:ok, execution} =
          Ash.update(execution, %{status: :running, started_at: DateTime.utc_now()})

        # Execute based on node type
        result = execute_node(String.to_existing_atom(node_type), config || %{}, context || %{})

        case result do
          {:ok, output} ->
            # Update execution record
            Ash.update(execution, %{
              status: :completed,
              result: output,
              finished_at: DateTime.utc_now()
            })

            # Notify orchestrator
            CampaignOrchestrator.node_completed(run_id, node_id, output)
            :ok

          {:error, error} ->
            # Update execution record
            Ash.update(execution, %{
              status: :failed,
              error_message: inspect(error),
              finished_at: DateTime.utc_now()
            })

            # Notify orchestrator
            CampaignOrchestrator.node_failed(run_id, node_id, error)
            {:error, error}
        end

      {:error, _} ->
        Logger.error("Workflow node execution #{execution_id} not found")
        {:error, :execution_not_found}
    end
  end

  defp execute_node(:mission, config, context) do
    MissionExecutor.execute(config, context)
  end

  defp execute_node(:conditional, config, context) do
    ConditionalExecutor.execute(config, context)
  end

  defp execute_node(:delay, config, context) do
    DelayExecutor.execute(config, context)
  end

  defp execute_node(:loop, config, context) do
    LoopExecutor.execute(config, context)
  end

  defp execute_node(unknown_type, _config, _context) do
    {:error, {:unknown_node_type, unknown_type}}
  end
end
