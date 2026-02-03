defmodule InvaderWeb.MissionLive.Show do
  @moduledoc """
  LiveView for viewing mission details including wave history.
  """
  use InvaderWeb, :live_view

  alias Invader.Agents.AgentConfig
  alias Invader.Missions
  alias Invader.Saves
  alias Invader.SpriteCli.Cli

  import InvaderWeb.PageLayout

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Missions.Mission.get(id) do
      {:ok, mission} ->
        mission = Ash.load!(mission, [:sprite, :waves])
        checkpoints = Saves.Save.for_mission!(mission.id)

        socket = maybe_subscribe_to_wave(socket, mission)

        {:ok,
         socket
         |> assign(:page_title, "Mission Details")
         |> assign(:mission, mission)
         |> assign(:checkpoints, checkpoints)
         |> assign(:expanded_waves, MapSet.new())
         |> assign(:live_output, "")}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Mission not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp maybe_subscribe_to_wave(socket, mission) do
    if socket.assigns[:subscribed_wave_topic] do
      Phoenix.PubSub.unsubscribe(Invader.PubSub, socket.assigns.subscribed_wave_topic)
    end

    running_wave = Enum.find(mission.waves, &is_nil(&1.exit_code))

    if running_wave && connected?(socket) do
      topic = "wave:#{running_wave.id}"
      Phoenix.PubSub.subscribe(Invader.PubSub, topic)

      socket
      |> assign(:subscribed_wave_topic, topic)
      |> assign(:running_wave_id, running_wave.id)
    else
      socket
      |> assign(:subscribed_wave_topic, nil)
      |> assign(:running_wave_id, nil)
    end
  end

  @impl true
  def handle_info({:wave_output, chunk}, socket) do
    {:noreply, assign(socket, :live_output, socket.assigns.live_output <> chunk)}
  end

  @impl true
  def handle_info({:mission_updated, _mission}, socket) do
    case Missions.Mission.get(socket.assigns.mission.id) do
      {:ok, mission} ->
        mission = Ash.load!(mission, [:sprite, :waves])
        checkpoints = Saves.Save.for_mission!(mission.id)
        socket = maybe_subscribe_to_wave(socket, mission)

        {:noreply,
         socket
         |> assign(:mission, mission)
         |> assign(:checkpoints, checkpoints)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_wave", %{"wave-id" => wave_id}, socket) do
    expanded =
      if wave_id in socket.assigns.expanded_waves do
        MapSet.delete(socket.assigns.expanded_waves, wave_id)
      else
        MapSet.put(socket.assigns.expanded_waves, wave_id)
      end

    {:noreply, assign(socket, :expanded_waves, expanded)}
  end

  @impl true
  def handle_event("restore_save", %{"id" => id}, socket) do
    case Saves.Save.get(id) do
      {:ok, save} ->
        save = Ash.load!(save, :sprite)
        Invader.SpriteCli.Cli.restore(save.sprite.name, save.checkpoint_id)
        {:noreply, put_flash(socket, :info, "Restored checkpoint #{save.checkpoint_id}")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_save", %{"id" => id}, socket) do
    case Saves.Save.get(id) do
      {:ok, save} ->
        Ash.destroy!(save)
        checkpoints = Saves.Save.for_mission!(socket.assigns.mission.id)

        {:noreply,
         socket |> assign(:checkpoints, checkpoints) |> put_flash(:info, "Checkpoint deleted")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_mission", _params, socket) do
    mission = socket.assigns.mission

    case Missions.Mission.start(mission) do
      {:ok, _} ->
        Invader.Workers.LoopRunner.enqueue(mission.id)
        mission = Ash.load!(Missions.Mission.get!(mission.id), [:sprite, :waves])
        {:noreply, socket |> assign(:mission, mission) |> put_flash(:info, "Mission started")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Mission cannot be started")}
    end
  end

  @impl true
  def handle_event("pause_mission", _params, socket) do
    mission = socket.assigns.mission

    case Missions.Mission.pause(mission) do
      {:ok, _} ->
        Invader.SpriteCli.Cli.kill_mission(mission.id)
        mission = Ash.load!(Missions.Mission.get!(mission.id), [:sprite, :waves])
        {:noreply, assign(socket, :mission, mission)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Mission cannot be paused")}
    end
  end

  @impl true
  def handle_event("resume_mission", _params, socket) do
    mission = socket.assigns.mission

    case Missions.Mission.resume(mission) do
      {:ok, _} ->
        Invader.Workers.LoopRunner.enqueue(mission.id)
        mission = Ash.load!(Missions.Mission.get!(mission.id), [:sprite, :waves])
        {:noreply, assign(socket, :mission, mission)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Mission cannot be resumed")}
    end
  end

  @impl true
  def handle_event("abort_mission", _params, socket) do
    mission = socket.assigns.mission

    case Missions.Mission.abort(mission) do
      {:ok, _} ->
        Invader.SpriteCli.Cli.kill_mission(mission.id)
        mission = Ash.load!(Missions.Mission.get!(mission.id), [:sprite, :waves])
        {:noreply, assign(socket, :mission, mission)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Mission cannot be aborted")}
    end
  end

  @impl true
  def handle_event("delete_mission", _params, socket) do
    Ash.destroy!(socket.assigns.mission)

    {:noreply,
     socket
     |> put_flash(:info, "Mission deleted")
     |> push_navigate(to: ~p"/")}
  end

  @impl true
  def handle_event("mark_setup_complete", _params, socket) do
    mission = socket.assigns.mission

    case Missions.Mission.setup_complete(mission) do
      {:ok, _} ->
        mission = Ash.load!(Missions.Mission.get!(mission.id), [:sprite, :waves])

        {:noreply,
         socket
         |> assign(:mission, mission)
         |> put_flash(:info, "Setup complete - mission is ready to start")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to mark setup as complete")}
    end
  end

  @impl true
  def handle_event("increment_waves", _params, socket) do
    mission = socket.assigns.mission
    new_max = mission.max_waves + 1

    case Missions.Mission.update_waves(mission, %{max_waves: new_max}) do
      {:ok, updated} ->
        updated = Ash.load!(updated, [:sprite, :waves])
        {:noreply, assign(socket, :mission, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot update waves")}
    end
  end

  @impl true
  def handle_event("decrement_waves", _params, socket) do
    mission = socket.assigns.mission
    new_max = max(mission.max_waves - 1, mission.current_wave + 1)

    case Missions.Mission.update_waves(mission, %{max_waves: new_max}) do
      {:ok, updated} ->
        updated = Ash.load!(updated, [:sprite, :waves])
        {:noreply, assign(socket, :mission, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot decrease waves below current wave")}
    end
  end

  @impl true
  def handle_event("inject_api_key", %{"api_key" => api_key}, socket) do
    mission = socket.assigns.mission

    if api_key && api_key != "" do
      case Cli.inject_agent_config(mission.sprite.name, mission.agent_provider, api_key) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "API key injected successfully")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to inject API key: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please enter an API key")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.arcade_page page_title="MISSION DETAILS">
      <:header_actions>
        <%= case @mission.status do %>
          <% :pending -> %>
            <button
              phx-click="start_mission"
              class="arcade-btn border-green-500 text-green-400 text-[8px] py-1.5 px-2"
            >
              START
            </button>
          <% :running -> %>
            <button
              phx-click="pause_mission"
              class="arcade-btn border-yellow-500 text-yellow-400 text-[8px] py-1.5 px-2"
            >
              PAUSE
            </button>
          <% :paused -> %>
            <button
              phx-click="resume_mission"
              class="arcade-btn border-green-500 text-green-400 text-[8px] py-1.5 px-2"
            >
              RESUME
            </button>
          <% _ -> %>
        <% end %>
        <%= if @mission.status in [:running, :pausing, :paused] do %>
          <button
            phx-click="abort_mission"
            data-confirm="Are you sure you want to abort this mission?"
            class="arcade-btn border-red-500 text-red-400 text-[8px] py-1.5 px-2"
          >
            ABORT
          </button>
        <% end %>
      </:header_actions>

      <div class="space-y-6">
        <!-- Mission Info -->
        <div class="grid grid-cols-2 gap-4 text-sm">
          <div>
            <span class="text-cyan-600">SPRITE</span>
            <div class="text-cyan-400">
              {@mission.sprite && @mission.sprite.name || @mission.sprite_name}
              <%= if @mission.status == :provisioning do %>
                <span class="text-orange-400 text-[8px] ml-2 animate-pulse">PROVISIONING...</span>
              <% end %>
            </div>
          </div>
          <div>
            <span class="text-cyan-600">STATUS</span>
            <div class={status_text_class(@mission.status)}>
              {status_label(@mission.status)}
            </div>
          </div>
          <div>
            <span class="text-cyan-600">PROMPT</span>
            <div class="text-cyan-400 truncate" title={@mission.prompt_path || "inline"}>
              {prompt_display(@mission)}
            </div>
          </div>
          <div>
            <span class="text-cyan-600">PROGRESS</span>
            <div class="text-cyan-400 flex items-center gap-2">
              <span>Wave {display_wave(@mission)}/</span>
              <%= if @mission.status in [:pending, :running, :pausing, :paused, :provisioning, :setup] do %>
                <div class="flex items-center gap-1">
                  <button
                    phx-click="decrement_waves"
                    class="w-5 h-5 flex items-center justify-center border border-cyan-700 text-cyan-500 hover:bg-cyan-900/30 text-xs"
                    title="Decrease max waves"
                  >
                    -
                  </button>
                  <span class="w-6 text-center">{@mission.max_waves}</span>
                  <button
                    phx-click="increment_waves"
                    class="w-5 h-5 flex items-center justify-center border border-cyan-700 text-cyan-500 hover:bg-cyan-900/30 text-xs"
                    title="Increase max waves"
                  >
                    +
                  </button>
                </div>
              <% else %>
                <span>{@mission.max_waves}</span>
              <% end %>
            </div>
          </div>
          <div>
            <span class="text-cyan-600">PRIORITY</span>
            <div class="text-cyan-400">{@mission.priority}</div>
          </div>
          <div>
            <span class="text-cyan-600">DURATION</span>
            <div class="text-cyan-400">
              {format_duration(@mission)}
            </div>
          </div>
        </div>

      <!-- Inline Prompt Content -->
        <%= if @mission.prompt && !@mission.prompt_path do %>
          <div class="border border-cyan-800 rounded p-3 bg-cyan-950/20">
            <div class="flex items-center justify-between mb-2">
              <span class="text-cyan-600 text-sm">INLINE PROMPT</span>
            </div>
            <pre class="text-cyan-400 text-xs whitespace-pre-wrap font-mono max-h-48 overflow-y-auto">{@mission.prompt}</pre>
          </div>
        <% end %>

        <%= if @mission.error_message do %>
          <div class="border border-red-700 rounded p-3 bg-red-950/30">
            <span class="text-red-500 text-sm">ERROR</span>
            <div class="text-red-400 text-sm mt-1">{@mission.error_message}</div>
          </div>
        <% end %>
        
    <!-- Setup Required Banner (for provisioning/setup states) -->
        <%= if @mission.status == :provisioning do %>
          <div class="border border-yellow-700 rounded p-4 bg-yellow-950/30">
            <div class="flex items-center gap-2 mb-2">
              <span class="w-2 h-2 bg-yellow-500 rounded-full animate-pulse"></span>
              <span class="text-yellow-500 text-sm font-bold">PROVISIONING SPRITE</span>
            </div>
            <p class="text-yellow-400 text-xs">
              Your sprite "{@mission.sprite_name}" is being created. This usually takes 1-2 minutes.
            </p>
          </div>
        <% end %>

        <%= if @mission.status == :setup do %>
          <div class="border border-cyan-700 rounded p-4 bg-cyan-950/30 space-y-4">
            <div class="flex items-center gap-2">
              <span class="text-cyan-500 text-sm font-bold">SETUP REQUIRED</span>
            </div>
            <p class="text-cyan-400 text-xs">
              Your sprite is ready. Configure the coding agent before starting the mission.
            </p>

            <div class="space-y-3">
              <div class="text-cyan-500 text-[10px]">OPTION 1: MANUAL LOGIN (RECOMMENDED)</div>
              <div class="bg-black p-3 rounded border border-cyan-900 flex items-center justify-between gap-2">
                <code class="text-cyan-400 text-xs font-mono">
                  sprite console -o {@mission.sprite.org} -s {@mission.sprite.name}
                </code>
                <button
                  phx-hook="CopyToClipboard"
                  id={"copy-console-cmd-#{@mission.id}"}
                  data-clipboard-text={"sprite console -o #{@mission.sprite.org} -s #{@mission.sprite.name}"}
                  class="text-cyan-500 hover:text-cyan-400 text-[10px] border border-cyan-700 px-2 py-1 rounded hover:border-cyan-500"
                  title="Copy to clipboard"
                >
                  COPY
                </button>
              </div>
              <p class="text-cyan-600 text-[9px]">{agent_auth_hint(@mission.agent_type)}</p>
            </div>

            <%= if @mission.agent_provider do %>
              <div class="space-y-3 pt-3 border-t border-cyan-900">
                <div class="text-cyan-500 text-[10px]">OPTION 2: API KEY INJECTION</div>
                <form phx-submit="inject_api_key" class="space-y-2">
                  <div class="flex gap-2">
                    <input
                      type="password"
                      name="api_key"
                      placeholder={"#{provider_name(@mission.agent_provider)} API Key..."}
                      class="flex-1 bg-black border-2 border-cyan-700 text-white p-2 text-xs focus:border-cyan-400 focus:outline-none"
                    />
                    <button
                      type="submit"
                      class="arcade-btn border-cyan-600 text-cyan-400 text-[8px] py-2 px-3"
                    >
                      INJECT
                    </button>
                  </div>
                </form>
              </div>
            <% end %>

            <div class="pt-3 border-t border-cyan-900">
              <button
                phx-click="mark_setup_complete"
                class="arcade-btn border-green-600 text-green-400 text-[10px] py-2 px-4"
              >
                MARK SETUP COMPLETE
              </button>
            </div>
          </div>
        <% end %>
        
    <!-- Checkpoints -->
        <%= if not Enum.empty?(@checkpoints) do %>
          <div>
            <h3 class="text-cyan-400 font-bold mb-3 flex items-center gap-2">
              <span>---</span> CHECKPOINTS
            </h3>
            <div class="space-y-2 max-h-40 overflow-y-auto">
              <%= for checkpoint <- @checkpoints do %>
                <div class="border border-cyan-800 p-2 flex justify-between items-center hover:bg-cyan-950/30">
                  <div>
                    <div class="text-cyan-400 text-xs">
                      {checkpoint.comment || "WAVE-#{checkpoint.wave_number}"}
                    </div>
                    <div class="text-[8px] text-cyan-700">
                      {format_checkpoint_time(checkpoint.inserted_at)}
                    </div>
                  </div>
                  <div class="flex gap-2">
                    <button
                      phx-click="restore_save"
                      phx-value-id={checkpoint.id}
                      class="px-2 py-1 border border-cyan-600 text-cyan-400 text-[8px] hover:bg-cyan-900/30"
                    >
                      RESTORE
                    </button>
                    <button
                      phx-click="delete_save"
                      phx-value-id={checkpoint.id}
                      data-confirm="Delete this checkpoint?"
                      class="px-2 py-1 border border-red-700 text-red-400 text-[8px] hover:bg-red-900/30"
                    >
                      DEL
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
        
    <!-- Wave History -->
        <div>
          <h3 class="text-cyan-400 font-bold mb-3 flex items-center gap-2">
            <span>---</span> WAVE HISTORY
          </h3>

          <%= if Enum.empty?(@mission.waves) do %>
            <p class="text-cyan-600 text-center py-4">NO WAVES RECORDED</p>
          <% else %>
            <div class="space-y-2 max-h-96 overflow-y-auto">
              <%= for wave <- Enum.sort_by(@mission.waves, & &1.number, :desc) do %>
                <div class="border border-cyan-800 rounded">
                  <button
                    type="button"
                    phx-click="toggle_wave"
                    phx-value-wave-id={wave.id}
                    class="w-full p-2 flex justify-between items-center text-left hover:bg-cyan-950/30"
                  >
                    <div class="flex items-center gap-3">
                      <span class="text-cyan-600">#{wave.number}</span>
                      <span class={exit_code_class(wave.exit_code)}>
                        {exit_code_label(wave.exit_code)}
                      </span>
                    </div>
                    <div class="flex items-center gap-3 text-xs text-cyan-700">
                      <span>{format_wave_duration(wave)}</span>
                      <.icon
                        name={
                          if wave.id in @expanded_waves,
                            do: "hero-chevron-up",
                            else: "hero-chevron-down"
                        }
                        class="size-4"
                      />
                    </div>
                  </button>

                  <%= if wave.id in @expanded_waves do %>
                    <div class="border-t border-cyan-800 p-2">
                      <%= cond do %>
                        <% wave.id == @running_wave_id and @live_output != "" -> %>
                          <div class="relative">
                            <div class="absolute top-1 right-1 flex items-center gap-1">
                              <span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                              <span class="text-[8px] text-green-500">LIVE</span>
                            </div>
                            <pre
                              id={"live-output-#{wave.id}"}
                              phx-hook="ScrollToBottom"
                              class="text-xs text-cyan-500 bg-black p-2 pt-6 rounded overflow-x-auto max-h-48 overflow-y-auto font-mono whitespace-pre-wrap"
                            >{@live_output}</pre>
                          </div>
                        <% wave.output -> %>
                          <div class="bg-black p-3 rounded overflow-x-auto max-h-48 overflow-y-auto markdown-content">
                            {render_markdown(wave.output)}
                          </div>
                        <% wave.id == @running_wave_id -> %>
                          <p class="text-cyan-600 text-xs flex items-center gap-2">
                            <span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                            Waiting for output...
                          </p>
                        <% true -> %>
                          <p class="text-cyan-700 text-xs">No output captured</p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Actions -->
        <div class="flex justify-between gap-3 pt-4 border-t border-cyan-800">
          <div>
            <%= if @mission.status == :pending do %>
              <button
                phx-click="delete_mission"
                data-confirm="Delete this mission? This action cannot be undone."
                class="px-4 py-2 border border-red-700 text-red-600 rounded hover:bg-red-900/30 text-sm"
              >
                DELETE
              </button>
            <% end %>
          </div>
          <div class="flex gap-3">
            <%= if @mission.status == :pending do %>
              <.link
                navigate={~p"/missions/#{@mission.id}/edit"}
                class="px-4 py-2 border border-blue-600 text-blue-400 rounded hover:bg-blue-900/30 text-sm"
              >
                EDIT
              </.link>
            <% end %>
          </div>
        </div>
      </div>
    </.arcade_page>
    """
  end

  defp prompt_display(%{prompt_path: path}) when is_binary(path), do: Path.basename(path)
  defp prompt_display(%{prompt: prompt}) when is_binary(prompt), do: "[inline]"
  defp prompt_display(_), do: "-"

  # Show active wave number (current_wave + 1) for running missions,
  # or completed wave count for finished missions
  defp display_wave(%{status: status, current_wave: current_wave, max_waves: max_waves})
       when status in [:running, :pausing, :paused] do
    min(current_wave + 1, max_waves)
  end

  defp display_wave(%{status: :pending, current_wave: current_wave}) do
    current_wave + 1
  end

  defp display_wave(%{current_wave: current_wave}), do: current_wave

  defp status_text_class(:completed), do: "text-green-400"
  defp status_text_class(:failed), do: "text-red-400"
  defp status_text_class(:aborted), do: "text-yellow-400"
  defp status_text_class(:running), do: "text-green-400 animate-pulse"
  defp status_text_class(:pausing), do: "text-yellow-400 animate-pulse"
  defp status_text_class(:paused), do: "text-yellow-400"
  defp status_text_class(:provisioning), do: "text-yellow-400 animate-pulse"
  defp status_text_class(:setup), do: "text-cyan-400"
  defp status_text_class(_), do: "text-cyan-400"

  defp status_label(:pausing), do: "PAUSING..."
  defp status_label(:provisioning), do: "PROVISIONING..."
  defp status_label(:setup), do: "SETUP REQUIRED"
  defp status_label(status), do: status |> to_string() |> String.upcase()

  defp exit_code_class(nil), do: "text-cyan-600"
  defp exit_code_class(0), do: "text-green-400"
  defp exit_code_class(_), do: "text-red-400"

  defp exit_code_label(nil), do: "running..."
  defp exit_code_label(0), do: "OK"
  defp exit_code_label(code), do: "exit #{code}"

  defp format_duration(%{waves: waves, status: status, finished_at: mission_finished_at})
       when is_list(waves) do
    end_time =
      if status in [:completed, :failed, :aborted] and mission_finished_at do
        mission_finished_at
      else
        DateTime.utc_now()
      end

    diff =
      waves
      |> Enum.reduce(0, fn wave, acc ->
        case {wave.started_at, wave.finished_at} do
          {nil, _} -> acc
          {started, nil} -> acc + DateTime.diff(end_time, started, :second)
          {started, finished} -> acc + DateTime.diff(finished, started, :second)
        end
      end)

    if diff == 0 and status in [:running, :pausing] do
      "in progress"
    else
      format_seconds(diff)
    end
  end

  defp format_duration(_), do: "-"

  defp format_seconds(diff) do
    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m #{rem(diff, 60)}s"
      true -> "#{div(diff, 3600)}h #{rem(div(diff, 60), 60)}m"
    end
  end

  defp format_wave_duration(%{started_at: nil}), do: "-"
  defp format_wave_duration(%{finished_at: nil}), do: "running..."

  defp format_wave_duration(%{started_at: started, finished_at: finished}) do
    diff = DateTime.diff(finished, started, :second)
    "#{diff}s"
  end

  defp format_checkpoint_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp render_markdown(text) when is_binary(text) do
    options = [
      extension: [strikethrough: true, table: true, tasklist: true],
      render: [unsafe: true]
    ]

    text
    |> MDEx.to_html!(options)
    |> Phoenix.HTML.raw()
  end

  defp render_markdown(_), do: ""

  defp agent_auth_hint(agent_type) do
    AgentConfig.auth_hint_for(agent_type)
  end

  defp provider_name(provider) do
    case AgentConfig.get_provider(provider) do
      nil -> "Custom"
      config -> config.name
    end
  end
end
