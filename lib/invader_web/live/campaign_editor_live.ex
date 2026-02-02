defmodule InvaderWeb.CampaignEditorLive do
  @moduledoc """
  Visual node-graph editor for campaigns.
  """
  use InvaderWeb, :live_view

  alias Invader.Campaigns.Campaign
  alias Invader.Campaigns.CampaignNode
  alias Invader.Campaigns.CampaignEdge
  alias Invader.Campaigns.CampaignRun
  alias Invader.Sprites

  import InvaderWeb.CampaignComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id) do
      {:ok, workflow} ->
        workflow = Ash.load!(workflow, [:nodes, :edges])
        sprites = Sprites.Sprite.list!()

        socket =
          socket
          |> assign(:page_title, "Edit Campaign: #{workflow.name}")
          |> assign(:workflow, workflow)
          |> assign(:nodes, workflow.nodes)
          |> assign(:edges, workflow.edges)
          |> assign(:sprites, sprites)
          |> assign(:selected_node, nil)
          |> assign(:selected_edge, nil)

        {:ok, socket}

      {:error, _} ->
        socket =
          socket
          |> put_flash(:error, "Campaign not found")
          |> push_navigate(to: ~p"/workflows")

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_node", %{"type" => type}, socket) do
    node_type = String.to_existing_atom(type)

    # Find a position that doesn't overlap with existing nodes
    {x, y} = find_open_position(socket.assigns.nodes)

    # Determine if this should be start node (first node is always start)
    is_start = Enum.empty?(socket.assigns.nodes)

    case CampaignNode.create(%{
           workflow_id: socket.assigns.workflow.id,
           node_type: node_type,
           position_x: x,
           position_y: y,
           is_start: is_start
         }) do
      {:ok, node} ->
        nodes = socket.assigns.nodes ++ [node]
        {:noreply, assign(socket, :nodes, nodes)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create node")}
    end
  end

  @impl true
  def handle_event("node_moved", %{"node_id" => node_id, "x" => x, "y" => y}, socket) do
    case CampaignNode.get(node_id) do
      {:ok, node} ->
        case CampaignNode.update(node, %{position_x: x, position_y: y}) do
          {:ok, updated_node} ->
            nodes = update_node_in_list(socket.assigns.nodes, updated_node)
            {:noreply, assign(socket, :nodes, nodes)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("node_selected", %{"node_id" => node_id}, socket) do
    node = Enum.find(socket.assigns.nodes, &(&1.id == node_id))

    socket =
      socket
      |> assign(:selected_node, node)
      |> assign(:selected_edge, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edge_selected", %{"edge_id" => edge_id}, socket) do
    edge = Enum.find(socket.assigns.edges, &(&1.id == edge_id))

    socket =
      socket
      |> assign(:selected_node, nil)
      |> assign(:selected_edge, edge)

    {:noreply, socket}
  end

  @impl true
  def handle_event("node_deleted", %{"node_id" => node_id}, socket) do
    case CampaignNode.get(node_id) do
      {:ok, node} ->
        Ash.destroy!(node)

        nodes = Enum.reject(socket.assigns.nodes, &(&1.id == node_id))

        edges =
          Enum.reject(socket.assigns.edges, fn edge ->
            edge.source_node_id == node_id or edge.target_node_id == node_id
          end)

        socket =
          socket
          |> assign(:nodes, nodes)
          |> assign(:edges, edges)
          |> assign(:selected_node, nil)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edge_deleted", %{"edge_id" => edge_id}, socket) do
    case CampaignEdge.get(edge_id) do
      {:ok, edge} ->
        Ash.destroy!(edge)

        edges = Enum.reject(socket.assigns.edges, &(&1.id == edge_id))

        socket =
          socket
          |> assign(:edges, edges)
          |> assign(:selected_edge, nil)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "edge_created",
        %{"source_node_id" => source_id, "target_node_id" => target_id},
        socket
      ) do
    # Check if edge already exists
    edge_exists? =
      Enum.any?(socket.assigns.edges, fn edge ->
        edge.source_node_id == source_id and edge.target_node_id == target_id
      end)

    if edge_exists? do
      {:noreply, socket}
    else
      # Detect if this is a loop-back edge (target appears before source in topological order)
      is_loop_back =
        is_loop_back_edge?(socket.assigns.nodes, socket.assigns.edges, source_id, target_id)

      case CampaignEdge.create(%{
             workflow_id: socket.assigns.workflow.id,
             source_node_id: source_id,
             target_node_id: target_id,
             is_loop_back: is_loop_back
           }) do
        {:ok, edge} ->
          edges = socket.assigns.edges ++ [edge]
          {:noreply, assign(socket, :edges, edges)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create edge")}
      end
    end
  end

  @impl true
  def handle_event("update_node_properties", params, socket) do
    node_id = params["node_id"]

    case CampaignNode.get(node_id) do
      {:ok, node} ->
        updates = %{
          label: params["label"],
          is_start: params["is_start"] == "true",
          config: params["config"] || %{}
        }

        # If setting this as start node, unset any existing start node
        if updates.is_start and not node.is_start do
          unset_other_start_nodes(socket.assigns.nodes, node_id)
        end

        case CampaignNode.update(node, updates) do
          {:ok, updated_node} ->
            nodes =
              if updates.is_start and not node.is_start do
                # Update all nodes - unset other start nodes and set this one
                socket.assigns.nodes
                |> Enum.map(fn n ->
                  cond do
                    n.id == node_id -> updated_node
                    n.is_start -> %{n | is_start: false}
                    true -> n
                  end
                end)
              else
                update_node_in_list(socket.assigns.nodes, updated_node)
              end

            socket =
              socket
              |> assign(:nodes, nodes)
              |> assign(:selected_node, updated_node)

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update node")}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_selected_node", _params, socket) do
    if socket.assigns.selected_node do
      handle_event("node_deleted", %{"node_id" => socket.assigns.selected_node.id}, socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_workflow", _params, socket) do
    # Save layout data (all node positions)
    layout_data =
      socket.assigns.nodes
      |> Enum.map(fn node ->
        {node.id, %{x: node.position_x, y: node.position_y}}
      end)
      |> Map.new()

    case Campaign.update(socket.assigns.workflow, %{layout_data: layout_data}) do
      {:ok, workflow} ->
        socket =
          socket
          |> assign(:workflow, workflow)
          |> put_flash(:info, "Campaign saved")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save campaign")}
    end
  end

  @impl true
  def handle_event("run_workflow", _params, socket) do
    # Create a new campaign run
    case CampaignRun.create(%{workflow_id: socket.assigns.workflow.id}) do
      {:ok, run} ->
        # Start the run
        case CampaignRun.start(run) do
          {:ok, _run} ->
            {:noreply, put_flash(socket, :info, "Campaign started")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to start campaign")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create campaign run")}
    end
  end

  # Private helpers

  defp find_open_position(nodes) do
    # Start at a base position and offset for each existing node
    base_x = 100
    base_y = 100
    offset = 180

    # Find the rightmost and bottommost positions
    {max_x, _max_y} =
      nodes
      |> Enum.reduce({base_x, base_y}, fn node, {mx, my} ->
        {max(mx, node.position_x), max(my, node.position_y)}
      end)

    # Place new node to the right of existing nodes
    {max_x + offset, base_y}
  end

  defp update_node_in_list(nodes, updated_node) do
    Enum.map(nodes, fn node ->
      if node.id == updated_node.id, do: updated_node, else: node
    end)
  end

  defp unset_other_start_nodes(nodes, except_id) do
    nodes
    |> Enum.filter(&(&1.is_start and &1.id != except_id))
    |> Enum.each(fn node ->
      CampaignNode.update(node, %{is_start: false})
    end)
  end

  defp is_loop_back_edge?(nodes, edges, source_id, target_id) do
    # Simple heuristic: if target node position is above source, it's likely a loop-back
    source = Enum.find(nodes, &(&1.id == source_id))
    target = Enum.find(nodes, &(&1.id == target_id))

    cond do
      is_nil(source) or is_nil(target) -> false
      target.position_y < source.position_y -> true
      # Also check if we can already reach source from target (would create a cycle)
      can_reach?(edges, target_id, source_id, MapSet.new()) -> true
      true -> false
    end
  end

  defp can_reach?(edges, from_id, to_id, visited) do
    if from_id == to_id do
      true
    else
      if MapSet.member?(visited, from_id) do
        false
      else
        visited = MapSet.put(visited, from_id)

        edges
        |> Enum.filter(&(&1.source_node_id == from_id))
        |> Enum.any?(fn edge ->
          can_reach?(edges, edge.target_node_id, to_id, visited)
        end)
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      class="arcade-container min-h-screen bg-black relative z-10"
      role="main"
    >
      <div class="crt-overlay pointer-events-none fixed inset-0 z-40" aria-hidden="true"></div>

      <div class="flex flex-col h-screen">
        <!-- Header -->
        <header class="flex items-center justify-between p-3 border-b-2 border-cyan-700">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/workflows"} class="text-cyan-500 hover:text-cyan-400 text-xs">
              ← BACK
            </.link>
            <h1 class="text-sm text-cyan-400 arcade-glow">
              {@workflow.name}
            </h1>
          </div>

          <div class="flex items-center gap-2">
            <button
              phx-click="save_workflow"
              class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-3"
            >
              SAVE
            </button>
            <button
              phx-click="run_workflow"
              class="arcade-btn border-green-500 text-green-400 text-[8px] py-1 px-3"
            >
              ▶ RUN
            </button>
          </div>
        </header>
        
    <!-- Toolbar -->
        <div class="p-2 border-b border-cyan-800">
          <.workflow_toolbar />
        </div>
        
    <!-- Main content area -->
        <div class="flex-1 flex overflow-hidden">
          <!-- Canvas -->
          <div class="flex-1 relative">
            <.workflow_canvas
              id="workflow-canvas"
              nodes={@nodes}
              edges={@edges}
              class="absolute inset-0"
            />
          </div>
          
    <!-- Properties panel -->
          <div class="w-64 border-l border-cyan-800 overflow-y-auto">
            <.workflow_properties node={@selected_node} sprites={@sprites} />
          </div>
        </div>
        
    <!-- Footer status -->
        <footer class="p-2 border-t border-cyan-800 flex items-center justify-between text-[8px] text-cyan-600">
          <span>
            NODES: {length(@nodes)} | EDGES: {length(@edges)}
          </span>
          <span>
            {if @selected_node,
              do: "Selected: #{@selected_node.label || @selected_node.node_type}",
              else: "No selection"}
          </span>
        </footer>
      </div>
    </main>
    """
  end
end
