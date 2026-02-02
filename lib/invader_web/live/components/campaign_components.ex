defmodule InvaderWeb.CampaignComponents do
  @moduledoc """
  Reusable UI components for the workflow editor.
  """
  use Phoenix.Component

  @doc """
  Renders the workflow canvas with nodes and edges.
  """
  attr :id, :string, required: true
  attr :nodes, :list, required: true
  attr :edges, :list, required: true
  attr :class, :string, default: nil

  def workflow_canvas(assigns) do
    edges_json =
      Jason.encode!(
        Enum.map(assigns.edges, fn edge ->
          %{
            id: edge.id,
            source_node_id: edge.source_node_id,
            target_node_id: edge.target_node_id,
            is_loop_back: edge.is_loop_back || false,
            label: edge.label
          }
        end)
      )

    assigns = assign(assigns, :edges_json, edges_json)

    ~H"""
    <div
      id={@id}
      phx-hook="WorkflowCanvas"
      class={["workflow-canvas", @class]}
    >
      <div class="workflow-canvas-bg"></div>
      <div class="workflow-transform-container">
        <svg class="workflow-edges-svg" data-edges={@edges_json}></svg>
        <div class="workflow-nodes-container">
          <.workflow_node :for={node <- @nodes} node={node} />
        </div>
      </div>
      <div class="workflow-zoom-controls">
        <button type="button" class="zoom-btn zoom-out">
          −
        </button>
        <select class="zoom-select">
          <option value="0.25">25%</option>
          <option value="0.50">50%</option>
          <option value="0.75">75%</option>
          <option value="1" selected>100%</option>
          <option value="1.50">150%</option>
          <option value="2">200%</option>
        </select>
        <button type="button" class="zoom-btn zoom-in">
          +
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single workflow node.
  """
  attr :node, :map, required: true

  def workflow_node(assigns) do
    ~H"""
    <div
      class={[
        "workflow-node",
        @node.is_start && "is-start"
      ]}
      data-node-id={@node.id}
      data-node-type={@node.node_type}
      data-x={@node.position_x}
      data-y={@node.position_y}
      style={"transform: translate(#{@node.position_x}px, #{@node.position_y}px)"}
    >
      <div class="workflow-port" data-port-type="input" data-port-index="0"></div>

      <div class="workflow-node-header">
        <span class="workflow-node-icon">{node_icon(@node.node_type)}</span>
        <span class="workflow-node-label">{@node.label || default_label(@node.node_type)}</span>
      </div>

      <div class="workflow-node-body">
        {node_summary(@node)}
      </div>

      <%= if @node.node_type == :conditional do %>
        <div class="workflow-port" data-port-type="output" data-port-index="0"></div>
        <div class="workflow-port" data-port-type="output" data-port-index="1"></div>
      <% else %>
        <div class="workflow-port" data-port-type="output" data-port-index="0"></div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the node palette toolbar.
  """
  attr :class, :string, default: nil

  def workflow_toolbar(assigns) do
    ~H"""
    <div class={["workflow-toolbar", @class]}>
      <button
        type="button"
        class="workflow-toolbar-item mission"
        phx-click="add_node"
        phx-value-type="mission"
        draggable="true"
      >
        <span>▶</span>
        <span>MISSION</span>
      </button>

      <button
        type="button"
        class="workflow-toolbar-item conditional"
        phx-click="add_node"
        phx-value-type="conditional"
        draggable="true"
      >
        <span>◇</span>
        <span>CONDITION</span>
      </button>

      <button
        type="button"
        class="workflow-toolbar-item delay"
        phx-click="add_node"
        phx-value-type="delay"
        draggable="true"
      >
        <span>⏱</span>
        <span>DELAY</span>
      </button>

      <button
        type="button"
        class="workflow-toolbar-item loop"
        phx-click="add_node"
        phx-value-type="loop"
        draggable="true"
      >
        <span>↻</span>
        <span>LOOP</span>
      </button>
    </div>
    """
  end

  @doc """
  Renders the properties panel for the selected node.
  """
  attr :node, :map, default: nil
  attr :sprites, :list, default: []

  def workflow_properties(assigns) do
    ~H"""
    <div class="workflow-properties">
      <%= if @node do %>
        <div class="workflow-properties-title">
          {String.upcase(to_string(@node.node_type))} PROPERTIES
        </div>

        <.node_properties_form node={@node} sprites={@sprites} />
      <% else %>
        <div class="workflow-properties-title">
          PROPERTIES
        </div>
        <p class="text-[8px] text-cyan-600">Select a node to edit its properties</p>
      <% end %>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :sprites, :list, default: []

  defp node_properties_form(assigns) do
    ~H"""
    <form phx-change="update_node_properties" phx-submit="update_node_properties">
      <input type="hidden" name="node_id" value={@node.id} />

      <div class="workflow-properties-field">
        <label class="workflow-properties-label">LABEL</label>
        <input
          type="text"
          name="label"
          value={@node.label}
          class="workflow-properties-input"
          placeholder={default_label(@node.node_type)}
        />
      </div>

      <div class="workflow-properties-field">
        <label class="workflow-properties-label flex items-center gap-2">
          <input
            type="checkbox"
            name="is_start"
            value="true"
            checked={@node.is_start}
            class="w-3 h-3"
          /> START NODE
        </label>
      </div>

      <%= case @node.node_type do %>
        <% :mission -> %>
          <.mission_properties node={@node} sprites={@sprites} />
        <% :conditional -> %>
          <.conditional_properties node={@node} />
        <% :delay -> %>
          <.delay_properties node={@node} />
        <% :loop -> %>
          <.loop_properties node={@node} />
        <% _ -> %>
      <% end %>

      <div class="mt-4 flex gap-2">
        <button type="submit" class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2">
          SAVE
        </button>
        <button
          type="button"
          phx-click="delete_selected_node"
          class="arcade-btn border-red-500 text-red-400 text-[8px] py-1 px-2"
        >
          DELETE
        </button>
      </div>
    </form>
    """
  end

  attr :node, :map, required: true
  attr :sprites, :list, default: []

  defp mission_properties(assigns) do
    config = assigns.node.config || %{}
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="workflow-properties-field">
      <label class="workflow-properties-label">SPRITE</label>
      <select name="config[sprite_id]" class="workflow-properties-input">
        <option value="">Select a sprite...</option>
        <%= for sprite <- @sprites do %>
          <option value={sprite.id} selected={@config["sprite_id"] == sprite.id}>
            {sprite.name}
          </option>
        <% end %>
      </select>
    </div>

    <div class="workflow-properties-field">
      <label class="workflow-properties-label">PROMPT</label>
      <textarea
        name="config[prompt]"
        class="workflow-properties-input h-20"
        placeholder="Mission prompt..."
      >{@config["prompt"]}</textarea>
    </div>

    <div class="workflow-properties-field">
      <label class="workflow-properties-label">MAX WAVES</label>
      <input
        type="number"
        name="config[max_waves]"
        value={@config["max_waves"] || 20}
        min="1"
        class="workflow-properties-input"
      />
    </div>
    """
  end

  attr :node, :map, required: true

  defp conditional_properties(assigns) do
    config = assigns.node.config || %{}
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="workflow-properties-field">
      <label class="workflow-properties-label">CONDITION</label>
      <textarea
        name="config[condition]"
        class="workflow-properties-input h-16"
        placeholder="Elixir expression returning true/false..."
      >{@config["condition"]}</textarea>
    </div>

    <div class="text-[7px] text-cyan-600 mt-1">
      Use <code class="text-cyan-400">context</code> to access workflow variables.
      Green port = true, Red port = false.
    </div>
    """
  end

  attr :node, :map, required: true

  defp delay_properties(assigns) do
    config = assigns.node.config || %{}
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="workflow-properties-field">
      <label class="workflow-properties-label">DELAY (SECONDS)</label>
      <input
        type="number"
        name="config[delay_seconds]"
        value={@config["delay_seconds"] || 60}
        min="1"
        class="workflow-properties-input"
      />
    </div>
    """
  end

  attr :node, :map, required: true

  defp loop_properties(assigns) do
    config = assigns.node.config || %{}
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="workflow-properties-field">
      <label class="workflow-properties-label">MAX ITERATIONS</label>
      <input
        type="number"
        name="config[max_iterations]"
        value={@config["max_iterations"] || 10}
        min="1"
        class="workflow-properties-input"
      />
    </div>

    <div class="workflow-properties-field">
      <label class="workflow-properties-label">CONTINUE CONDITION</label>
      <textarea
        name="config[continue_condition]"
        class="workflow-properties-input h-16"
        placeholder="Expression to continue looping..."
      >{@config["continue_condition"]}</textarea>
    </div>
    """
  end

  # Helper functions

  defp node_icon(:mission), do: "▶"
  defp node_icon(:conditional), do: "◇"
  defp node_icon(:delay), do: "⏱"
  defp node_icon(:loop), do: "↻"
  defp node_icon(_), do: "●"

  defp default_label(:mission), do: "Mission"
  defp default_label(:conditional), do: "Condition"
  defp default_label(:delay), do: "Delay"
  defp default_label(:loop), do: "Loop"
  defp default_label(_), do: "Node"

  defp node_summary(%{node_type: :mission, config: config}) when is_map(config) do
    if prompt = config["prompt"] do
      String.slice(prompt, 0, 30) <> if(String.length(prompt) > 30, do: "...", else: "")
    else
      "Configure mission..."
    end
  end

  defp node_summary(%{node_type: :conditional, config: config}) when is_map(config) do
    if condition = config["condition"] do
      String.slice(condition, 0, 25) <> if(String.length(condition) > 25, do: "...", else: "")
    else
      "if (condition)"
    end
  end

  defp node_summary(%{node_type: :delay, config: config}) when is_map(config) do
    seconds = config["delay_seconds"] || 60
    "Wait #{seconds}s"
  end

  defp node_summary(%{node_type: :loop, config: config}) when is_map(config) do
    max = config["max_iterations"] || 10
    "Max #{max} iterations"
  end

  defp node_summary(_), do: "..."
end
