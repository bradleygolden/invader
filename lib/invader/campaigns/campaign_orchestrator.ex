defmodule Invader.Campaigns.CampaignOrchestrator do
  @moduledoc """
  GenServer that orchestrates workflow execution.

  Responsibilities:
  - Evaluates DAG topology using libgraph
  - Determines ready nodes (all dependencies completed)
  - Enqueues Oban jobs for parallel execution
  - Tracks completion and triggers downstream nodes
  """
  use GenServer

  alias Invader.Campaigns.{CampaignRun, CampaignNodeExecution}

  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start executing a workflow run.
  """
  def execute(run_id) do
    GenServer.call(__MODULE__, {:execute, run_id})
  end

  @doc """
  Called when a node execution completes.
  """
  def node_completed(run_id, node_id, result) do
    GenServer.cast(__MODULE__, {:node_completed, run_id, node_id, result})
  end

  @doc """
  Called when a node execution fails.
  """
  def node_failed(run_id, node_id, error) do
    GenServer.cast(__MODULE__, {:node_failed, run_id, node_id, error})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{runs: %{}}}
  end

  @impl true
  def handle_call({:execute, run_id}, _from, state) do
    case CampaignRun.get(run_id) do
      {:ok, run} ->
        run = Ash.load!(run, workflow: [:nodes, :edges])

        # Build the graph
        graph = build_graph(run.workflow.nodes, run.workflow.edges)

        # Find the start node
        start_node = Enum.find(run.workflow.nodes, & &1.is_start)

        if start_node do
          # Initialize run state
          run_state = %{
            run_id: run_id,
            workflow_id: run.workflow_id,
            graph: graph,
            nodes: Map.new(run.workflow.nodes, &{&1.id, &1}),
            edges: run.workflow.edges,
            completed_nodes: MapSet.new(),
            failed_nodes: MapSet.new(),
            context: run.context || %{},
            iteration_counts: %{}
          }

          # Start the run
          case CampaignRun.start(run) do
            {:ok, _} ->
              # Enqueue the start node
              enqueue_node(run_state, start_node)

              new_state = put_in(state, [:runs, run_id], run_state)
              {:reply, :ok, new_state}

            {:error, error} ->
              {:reply, {:error, error}, state}
          end
        else
          {:reply, {:error, :no_start_node}, state}
        end

      {:error, _} ->
        {:reply, {:error, :run_not_found}, state}
    end
  end

  @impl true
  def handle_cast({:node_completed, run_id, node_id, result}, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:noreply, state}

      run_state ->
        # Mark node as completed
        run_state = update_in(run_state.completed_nodes, &MapSet.put(&1, node_id))

        # Update context with result if provided
        run_state =
          if result do
            update_in(run_state.context, &Map.merge(&1, result))
          else
            run_state
          end

        # Find and enqueue ready downstream nodes
        run_state = process_downstream_nodes(run_state, node_id)

        # Check if workflow is complete
        if workflow_complete?(run_state) do
          complete_workflow(run_state)
          new_state = Map.delete(state.runs, run_id)
          {:noreply, new_state}
        else
          new_state = put_in(state, [:runs, run_id], run_state)
          {:noreply, new_state}
        end
    end
  end

  @impl true
  def handle_cast({:node_failed, run_id, node_id, error}, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:noreply, state}

      run_state ->
        # Mark node as failed
        run_state = update_in(run_state.failed_nodes, &MapSet.put(&1, node_id))

        # Fail the entire workflow
        fail_workflow(run_state, error)

        new_state = Map.delete(state.runs, run_id)
        {:noreply, new_state}
    end
  end

  # Private functions

  defp build_graph(nodes, edges) do
    graph = Graph.new(type: :directed)

    # Add all nodes as vertices
    graph =
      Enum.reduce(nodes, graph, fn node, g ->
        Graph.add_vertex(g, node.id)
      end)

    # Add edges
    Enum.reduce(edges, graph, fn edge, g ->
      Graph.add_edge(g, edge.source_node_id, edge.target_node_id)
    end)
  end

  defp enqueue_node(run_state, node) do
    # Create node execution record
    iteration = Map.get(run_state.iteration_counts, node.id, 0) + 1

    case CampaignNodeExecution.create(%{
           run_id: run_state.run_id,
           node_id: node.id,
           iteration: iteration
         }) do
      {:ok, execution} ->
        # Enqueue the Oban job
        %{
          run_id: run_state.run_id,
          node_id: node.id,
          execution_id: execution.id,
          node_type: node.node_type,
          config: node.config,
          context: run_state.context
        }
        |> Invader.Workers.CampaignNodeRunner.new()
        |> Oban.insert()

      {:error, error} ->
        Logger.error("Failed to create node execution: #{inspect(error)}")
    end
  end

  defp process_downstream_nodes(run_state, completed_node_id) do
    # Find outgoing edges from the completed node
    outgoing_edges =
      Enum.filter(run_state.edges, &(&1.source_node_id == completed_node_id))

    # For each downstream node, check if it's ready to execute
    Enum.reduce(outgoing_edges, run_state, fn edge, acc_state ->
      target_node = Map.get(acc_state.nodes, edge.target_node_id)

      if target_node && node_ready?(acc_state, target_node) do
        # Handle loop-back edges
        if edge.is_loop_back do
          handle_loop_back(acc_state, edge, target_node)
        else
          enqueue_node(acc_state, target_node)
          acc_state
        end
      else
        acc_state
      end
    end)
  end

  defp node_ready?(run_state, node) do
    # Get all incoming edges that are NOT loop-back edges
    incoming_edges =
      run_state.edges
      |> Enum.filter(&(&1.target_node_id == node.id and not &1.is_loop_back))

    # Check if all predecessor nodes are completed
    Enum.all?(incoming_edges, fn edge ->
      MapSet.member?(run_state.completed_nodes, edge.source_node_id)
    end)
  end

  defp handle_loop_back(run_state, edge, target_node) do
    current_iteration = Map.get(run_state.iteration_counts, target_node.id, 0)
    max_iterations = edge.max_iterations || 10

    if current_iteration < max_iterations do
      # Increment iteration count and enqueue
      run_state =
        update_in(run_state.iteration_counts, &Map.put(&1, target_node.id, current_iteration + 1))

      # Clear the node from completed so it can run again
      run_state = update_in(run_state.completed_nodes, &MapSet.delete(&1, target_node.id))

      enqueue_node(run_state, target_node)
      run_state
    else
      # Max iterations reached, don't loop back
      run_state
    end
  end

  defp workflow_complete?(run_state) do
    # Workflow is complete when all nodes without outgoing edges are completed
    terminal_nodes =
      run_state.nodes
      |> Map.keys()
      |> Enum.filter(fn node_id ->
        not Enum.any?(run_state.edges, &(&1.source_node_id == node_id))
      end)

    Enum.all?(terminal_nodes, &MapSet.member?(run_state.completed_nodes, &1))
  end

  defp complete_workflow(run_state) do
    case CampaignRun.get(run_state.run_id) do
      {:ok, run} ->
        CampaignRun.complete(run)

      _ ->
        :ok
    end
  end

  defp fail_workflow(run_state, error) do
    case CampaignRun.get(run_state.run_id) do
      {:ok, run} ->
        CampaignRun.fail(run, %{error_message: inspect(error)})

      _ ->
        :ok
    end
  end
end
