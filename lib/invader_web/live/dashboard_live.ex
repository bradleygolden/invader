defmodule InvaderWeb.DashboardLive do
  @moduledoc """
  8-bit Space Invaders themed dashboard for monitoring Ralph loops.
  """
  use InvaderWeb, :live_view

  alias Invader.Missions
  alias Invader.Sprites
  alias Invader.Saves
  alias InvaderWeb.TimezoneHelper

  @refresh_interval 5000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
      Phoenix.PubSub.subscribe(Invader.PubSub, "missions")
      Phoenix.PubSub.subscribe(Invader.PubSub, "settings")
    end

    socket =
      socket
      |> assign(:page_title, "Invader Dashboard")
      |> assign(:auto_start_queue, Invader.Settings.auto_start_queue?())
      |> assign(:timezone_mode, Invader.Settings.timezone_mode())
      |> assign(:time_format, Invader.Settings.time_format())
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Invader Dashboard")
    |> assign(:sprite, nil)
    |> assign(:mission, nil)
    |> assign(:save, nil)
  end

  defp apply_action(socket, :new_sprite, _params) do
    socket
    |> assign(:page_title, "New Sprite")
    |> assign(:sprite, %Sprites.Sprite{})
  end

  defp apply_action(socket, :edit_sprite, %{"id" => id}) do
    case Sprites.Sprite.get(id) do
      {:ok, sprite} ->
        socket
        |> assign(:page_title, "Edit Sprite")
        |> assign(:sprite, sprite)

      _ ->
        socket
        |> put_flash(:error, "Sprite not found")
        |> push_patch(to: ~p"/")
    end
  end

  defp apply_action(socket, :show_sprite, %{"id" => id}) do
    case Sprites.Sprite.get(id) do
      {:ok, sprite} ->
        socket
        |> assign(:page_title, "Sprite Details")
        |> assign(:sprite, sprite)

      _ ->
        socket
        |> put_flash(:error, "Sprite not found")
        |> push_patch(to: ~p"/")
    end
  end

  defp apply_action(socket, :new_mission, _params) do
    socket
    |> assign(:page_title, "New Mission")
    |> assign(:mission, %Missions.Mission{})
  end

  defp apply_action(socket, :edit_mission, %{"id" => id}) do
    case Missions.Mission.get(id) do
      {:ok, mission} ->
        mission = Ash.load!(mission, :sprite)

        socket
        |> assign(:page_title, "Edit Mission")
        |> assign(:mission, mission)

      _ ->
        socket
        |> put_flash(:error, "Mission not found")
        |> push_patch(to: ~p"/")
    end
  end

  defp apply_action(socket, :show_mission, %{"id" => id}) do
    case Missions.Mission.get(id) do
      {:ok, mission} ->
        mission = Ash.load!(mission, [:sprite, :waves])

        socket
        |> assign(:page_title, "Mission Details")
        |> assign(:mission, mission)

      _ ->
        socket
        |> put_flash(:error, "Mission not found")
        |> push_patch(to: ~p"/")
    end
  end

  defp apply_action(socket, :show_save, %{"id" => id}) do
    case Saves.Save.get(id) do
      {:ok, save} ->
        save = Ash.load!(save, [:sprite, :mission])

        socket
        |> assign(:page_title, "Save Details")
        |> assign(:save, save)

      _ ->
        socket
        |> put_flash(:error, "Save not found")
        |> push_patch(to: ~p"/")
    end
  end

  defp apply_action(socket, :settings, _params) do
    socket
    |> assign(:page_title, "Settings")
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:mission_updated, _mission}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({InvaderWeb.SpriteFormComponent, {:saved, _sprite}}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({InvaderWeb.MissionFormComponent, {:saved, _mission}}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:load_sprite_metrics, sprite_name, component_id}, socket) do
    # Load metrics asynchronously - capture self() for the callback
    parent = self()

    Task.start(fn ->
      case Invader.SpriteCli.Cli.get_metrics(sprite_name) do
        {:ok, metrics} ->
          send_update(parent, InvaderWeb.SpriteDetailComponent,
            id: component_id,
            sprite_metrics_loaded: metrics
          )

        {:error, reason} ->
          send_update(parent, InvaderWeb.SpriteDetailComponent,
            id: component_id,
            sprite_metrics_error: inspect(reason)
          )
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:settings_changed, :auto_start_queue, value}, socket) do
    {:noreply, assign(socket, :auto_start_queue, value)}
  end

  @impl true
  def handle_info({:settings_changed, :timezone_mode, value}, socket) do
    {:noreply, assign(socket, :timezone_mode, value)}
  end

  @impl true
  def handle_info({:settings_changed, :user_timezone, _value}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:settings_changed, :time_format, value}, socket) do
    {:noreply, assign(socket, :time_format, value)}
  end

  @impl true
  def handle_event("start_mission", %{"id" => id}, socket) do
    case Missions.Mission.get(id) do
      {:ok, mission} ->
        case Missions.Mission.start(mission) do
          {:ok, _} ->
            Invader.Workers.LoopRunner.enqueue(id)
            {:noreply, load_data(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Mission cannot be started")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("pause_mission", %{"id" => id}, socket) do
    case Missions.Mission.get(id) do
      {:ok, mission} ->
        case Missions.Mission.pause(mission) do
          {:ok, _} -> {:noreply, load_data(socket)}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Mission cannot be paused")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("resume_mission", %{"id" => id}, socket) do
    case Missions.Mission.get(id) do
      {:ok, mission} ->
        case Missions.Mission.resume(mission) do
          {:ok, _} ->
            Invader.Workers.LoopRunner.enqueue(id)
            {:noreply, load_data(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Mission cannot be resumed")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("abort_mission", %{"id" => id}, socket) do
    case Missions.Mission.get(id) do
      {:ok, mission} ->
        case Missions.Mission.abort(mission) do
          {:ok, _} -> {:noreply, load_data(socket)}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Mission cannot be aborted")}
        end

      _ ->
        {:noreply, socket}
    end
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
  def handle_event("delete_sprite", %{"id" => id}, socket) do
    case Sprites.Sprite.get(id) do
      {:ok, sprite} ->
        Ash.destroy!(sprite)

        {:noreply,
         socket
         |> put_flash(:info, "Sprite deleted")
         |> load_data()}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_mission", %{"id" => id}, socket) do
    case Missions.Mission.get(id) do
      {:ok, mission} ->
        Ash.destroy!(mission)

        {:noreply,
         socket
         |> put_flash(:info, "Mission deleted")
         |> push_patch(to: ~p"/")
         |> load_data()}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_save", %{"id" => id}, socket) do
    case Saves.Save.get(id) do
      {:ok, save} ->
        Ash.destroy!(save)

        {:noreply,
         socket
         |> put_flash(:info, "Save deleted")
         |> push_patch(to: ~p"/")
         |> load_data()}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("sync_sprites", _params, socket) do
    try do
      case Sprites.Sprite.sync() do
        {:ok, sprites} ->
          {:noreply,
           socket
           |> put_flash(:info, "Synced #{length(sprites)} sprites from CLI")
           |> load_data()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Sync failed: #{inspect(reason)}")}
      end
    rescue
      e in RuntimeError ->
        {:noreply, put_flash(socket, :error, e.message)}
    end
  end

  @impl true
  def handle_event("toggle_auto_start", _params, socket) do
    new_value = Invader.Settings.toggle_auto_start_queue()
    {:noreply, assign(socket, :auto_start_queue, new_value)}
  end

  @impl true
  def handle_event("toggle_timezone", _params, socket) do
    new_value = Invader.Settings.toggle_timezone_mode()
    {:noreply, assign(socket, :timezone_mode, new_value)}
  end

  @impl true
  def handle_event("set_user_timezone", %{"timezone" => timezone}, socket) do
    Invader.Settings.set_user_timezone(timezone)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_time_format", _params, socket) do
    new_value = Invader.Settings.toggle_time_format()
    {:noreply, assign(socket, :time_format, new_value)}
  end

  defp load_data(socket) do
    missions = Missions.Mission.list!() |> Ash.load!([:sprite, :waves])
    sprites = Sprites.Sprite.list!()
    saves = Saves.Save.list!() |> Ash.load!([:sprite]) |> Enum.take(20)

    running = Enum.filter(missions, &(&1.status == :running))

    pending =
      missions
      |> Enum.filter(&(&1.status == :pending))
      |> Enum.sort_by(& &1.priority, :desc)

    completed = Enum.filter(missions, &(&1.status in [:completed, :failed, :aborted]))

    socket
    |> assign(:running_missions, running)
    |> assign(:pending_missions, pending)
    |> assign(:completed_missions, completed)
    |> assign(:sprites, sprites)
    |> assign(:recent_saves, saves)
    |> assign(:stats, calculate_stats(missions))
  end

  defp calculate_stats(missions) do
    %{
      total: length(missions),
      completed: Enum.count(missions, &(&1.status == :completed)),
      failed: Enum.count(missions, &(&1.status == :failed)),
      total_waves: missions |> Enum.map(&length(&1.waves)) |> Enum.sum()
    }
  end

  defp prompt_display(%{prompt_path: path}) when is_binary(path), do: Path.basename(path)
  defp prompt_display(%{prompt: prompt}) when is_binary(prompt), do: "[inline]"
  defp prompt_display(_), do: "-"

  @impl true
  def render(assigns) do
    ~H"""
    <main
      class="arcade-container min-h-screen bg-black p-4 relative z-10"
      role="main"
      id="dashboard-main"
      phx-hook="TimezoneDetector"
    >
      <!-- CRT Scanlines Overlay -->
      <div class="crt-overlay pointer-events-none fixed inset-0 z-40" aria-hidden="true"></div>
      
    <!-- Modals -->
      <.modal
        :if={@live_action in [:new_sprite, :edit_sprite]}
        id={"sprite-modal-#{@live_action}"}
        show
      >
        <:title>{(@live_action == :new_sprite && "NEW SPRITE") || "EDIT SPRITE"}</:title>
        <.live_component
          module={InvaderWeb.SpriteFormComponent}
          id={@sprite.id || :new}
          sprite={@sprite}
          action={(@live_action == :new_sprite && :new) || :edit}
        />
      </.modal>

      <.modal
        :if={@live_action in [:new_mission, :edit_mission]}
        id={"mission-modal-#{@live_action}"}
        show
      >
        <:title>{(@live_action == :new_mission && "NEW MISSION") || "EDIT MISSION"}</:title>
        <.live_component
          module={InvaderWeb.MissionFormComponent}
          id={@mission.id || :new}
          mission={@mission}
          action={(@live_action == :new_mission && :new) || :edit}
        />
      </.modal>

      <.modal
        :if={@live_action == :show_mission}
        id={"mission-detail-modal-#{@mission && @mission.id}"}
        show
      >
        <:title>MISSION DETAILS</:title>
        <.live_component
          module={InvaderWeb.MissionDetailComponent}
          id={@mission.id}
          mission={@mission}
        />
      </.modal>

      <.modal
        :if={@live_action == :show_sprite}
        id={"sprite-detail-modal-#{@sprite && @sprite.id}"}
        show
      >
        <:title>SPRITE DETAILS</:title>
        <.live_component
          module={InvaderWeb.SpriteDetailComponent}
          id={@sprite.id}
          sprite={@sprite}
        />
      </.modal>

      <.modal :if={@live_action == :show_save} id={"save-detail-modal-#{@save && @save.id}"} show>
        <:title>SAVE DETAILS</:title>
        <div class="space-y-4">
          <div class="grid grid-cols-2 gap-4 text-xs">
            <div>
              <span class="text-cyan-500">SPRITE</span>
              <div class="text-white mt-1">{@save.sprite.name}</div>
            </div>
            <div>
              <span class="text-cyan-500">CHECKPOINT</span>
              <div class="text-white mt-1 text-[8px]">{@save.checkpoint_id}</div>
            </div>
            <div>
              <span class="text-cyan-500">WAVE</span>
              <div class="text-white mt-1">{@save.wave_number || "-"}</div>
            </div>
            <div>
              <span class="text-cyan-500">CREATED</span>
              <div class="text-white mt-1">{format_datetime(@save.inserted_at)}</div>
            </div>
          </div>
          <%= if @save.comment do %>
            <div>
              <span class="text-cyan-500 text-xs">COMMENT</span>
              <div class="text-white text-xs mt-1">{@save.comment}</div>
            </div>
          <% end %>
          <div class="flex justify-end gap-3 pt-4 border-t border-cyan-800">
            <.link
              patch={~p"/"}
              class="arcade-btn border-cyan-500 text-cyan-400 hover:bg-cyan-900/30"
            >
              CLOSE
            </.link>
            <button
              phx-click="restore_save"
              phx-value-id={@save.id}
              class="arcade-btn border-green-500 text-green-400 hover:bg-green-900/30"
            >
              RESTORE
            </button>
            <button
              phx-click="delete_save"
              phx-value-id={@save.id}
              data-confirm="Are you sure you want to delete this save?"
              class="arcade-btn border-red-500 text-red-400 hover:bg-red-900/30"
            >
              DELETE
            </button>
          </div>
        </div>
      </.modal>

      <.modal :if={@live_action == :settings} id="settings-modal" show>
        <:title>SETTINGS</:title>
        <div class="space-y-6">
          <!-- Timezone Setting -->
          <div class="space-y-2">
            <div class="flex justify-between items-center">
              <div>
                <div class="text-cyan-500 text-[10px]">TIME DISPLAY</div>
                <div class="text-cyan-700 text-[8px] mt-1">
                  Show times in UTC or your local timezone
                </div>
              </div>
              <button
                phx-click="toggle_timezone"
                class={"arcade-btn text-[10px] py-2 px-4 #{if @timezone_mode == :utc, do: "border-cyan-500 text-cyan-400", else: "border-fuchsia-500 text-fuchsia-400"}"}
              >
                {if @timezone_mode == :utc, do: "UTC", else: TimezoneHelper.timezone_label()}
              </button>
            </div>
          </div>
          
    <!-- Time Format Setting -->
          <div class="space-y-2">
            <div class="flex justify-between items-center">
              <div>
                <div class="text-cyan-500 text-[10px]">TIME FORMAT</div>
                <div class="text-cyan-700 text-[8px] mt-1">
                  Display time in 12-hour or 24-hour format
                </div>
              </div>
              <button
                phx-click="toggle_time_format"
                class="arcade-btn text-[10px] py-2 px-4 border-cyan-500 text-cyan-400"
              >
                {if @time_format == :"24h", do: "24H", else: "12H"}
              </button>
            </div>
          </div>
          
    <!-- Auto-start Queue Setting -->
          <div class="space-y-2">
            <div class="flex justify-between items-center">
              <div>
                <div class="text-cyan-500 text-[10px]">AUTO-START QUEUE</div>
                <div class="text-cyan-700 text-[8px] mt-1">
                  Automatically start next pending mission
                </div>
              </div>
              <button
                phx-click="toggle_auto_start"
                class={"arcade-btn text-[10px] py-2 px-4 #{if @auto_start_queue, do: "border-green-500 text-green-400", else: "border-cyan-700 text-cyan-600"}"}
              >
                {if @auto_start_queue, do: "ON", else: "OFF"}
              </button>
            </div>
          </div>
          
    <!-- Close Button -->
          <div class="flex justify-end pt-4 border-t border-cyan-800">
            <.link
              patch={~p"/"}
              class="arcade-btn border-cyan-500 text-cyan-400 hover:bg-cyan-900/30"
            >
              CLOSE
            </.link>
          </div>
        </div>
      </.modal>
      
    <!-- Animated Aliens Header Decoration -->
      <div class="flex justify-center gap-4 mb-2 text-2xl">
        <span class="alien-sprite text-cyan-400"></span>
        <span class="alien-sprite text-magenta-400" style="animation-delay: 0.2s;"></span>
        <span class="alien-sprite text-green-400" style="animation-delay: 0.4s;"></span>
        <span class="alien-sprite text-cyan-400" style="animation-delay: 0.6s;"></span>
        <span class="alien-sprite text-magenta-400" style="animation-delay: 0.8s;"></span>
      </div>
      
    <!-- Header -->
      <header class="text-center mb-6 relative">
        <.link
          patch={~p"/settings"}
          class="absolute right-0 top-0 arcade-btn border-cyan-700 text-cyan-500 text-[10px] py-1 px-2 hover:border-cyan-400 hover:text-cyan-400"
          title="Settings"
        >
          <span class="text-sm">⚙</span>
        </.link>
        <h1 class="text-3xl md:text-4xl font-bold tracking-widest arcade-glow">
          INVADER
        </h1>
        <p class="text-cyan-500 text-[10px] mt-3 tracking-wider">[ RALPH LOOP COMMAND CENTER ]</p>
      </header>
      
    <!-- Score Display - Classic Arcade Style -->
      <div class="flex justify-between items-start mb-6 px-2">
        <div class="text-left">
          <div class="text-[10px] text-white mb-1">SCORE&lt;1&gt;</div>
          <div class="text-xl text-white score-display">
            {String.pad_leading(to_string(@stats.completed * 100), 5, "0")}
          </div>
        </div>
        <div class="text-center">
          <div class="text-[10px] text-red-500 mb-1">HI-SCORE</div>
          <div class="text-xl text-white score-display">
            {String.pad_leading(to_string(@stats.total_waves * 10), 5, "0")}
          </div>
        </div>
        <div class="text-right">
          <div class="text-[10px] text-white mb-1">SCORE&lt;2&gt;</div>
          <div class="text-xl text-white score-display">
            {String.pad_leading(to_string(@stats.total * 50), 5, "0")}
          </div>
        </div>
      </div>
      
    <!-- Stats Bar -->
      <div class="grid grid-cols-4 gap-3 mb-6 text-center">
        <div class="arcade-panel p-3">
          <div class="text-2xl text-white">{@stats.total}</div>
          <div class="text-[8px] text-cyan-500 mt-1">MISSIONS</div>
        </div>
        <div class="arcade-panel p-3">
          <div class="text-2xl text-green-400">{@stats.completed}</div>
          <div class="text-[8px] text-cyan-500 mt-1">COMPLETED</div>
        </div>
        <div class="arcade-panel p-3">
          <div class="text-2xl text-red-500">{@stats.failed}</div>
          <div class="text-[8px] text-cyan-500 mt-1">DESTROYED</div>
        </div>
        <div class="arcade-panel p-3">
          <div class="text-2xl text-yellow-400">{@stats.total_waves}</div>
          <div class="text-[8px] text-cyan-500 mt-1">WAVES</div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <!-- Active Missions -->
        <section class="arcade-panel p-4">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-sm text-green-400 icon-text">
              <span class="text-sm">▶</span>
              <span>ACTIVE INVASION</span>
            </h2>
          </div>

          <%= if Enum.empty?(@running_missions) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- AWAITING ORDERS -</p>
          <% else %>
            <div class="space-y-3">
              <%= for mission <- @running_missions do %>
                <div class="border-2 border-green-500 p-3 bg-black/50 hover:bg-green-900/20 transition-colors">
                  <div class="flex justify-between items-start">
                    <.link
                      patch={~p"/missions/#{mission.id}"}
                      class="flex-1 cursor-pointer"
                    >
                      <div class="text-white text-xs">
                        <span class="text-green-400 mr-2">▸</span>
                        {mission.sprite.name}
                      </div>
                      <div class="text-[10px] text-cyan-400 mt-1">
                        WAVE {mission.current_wave}/{mission.max_waves}
                      </div>
                      <div class="text-[8px] text-cyan-700 truncate max-w-xs mt-1">
                        {prompt_display(mission)}
                      </div>
                    </.link>
                    <div class="flex gap-2">
                      <button
                        phx-click="pause_mission"
                        phx-value-id={mission.id}
                        class="arcade-btn border-yellow-500 text-yellow-400 text-[8px] py-1 px-2"
                      >
                        PAUSE
                      </button>
                      <button
                        phx-click="abort_mission"
                        phx-value-id={mission.id}
                        class="arcade-btn border-red-500 text-red-400 text-[8px] py-1 px-2"
                      >
                        ABORT
                      </button>
                    </div>
                  </div>
                  <!-- Progress bar - Laser style -->
                  <.link patch={~p"/missions/#{mission.id}"} class="block">
                    <div class="mt-3 h-2 bg-black border border-green-700 overflow-hidden cursor-pointer">
                      <div
                        class="h-full laser-progress transition-all duration-500"
                        style={"width: #{mission.current_wave / mission.max_waves * 100}%"}
                      >
                      </div>
                    </div>
                  </.link>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>
        
    <!-- Pending Queue -->
        <section class="arcade-panel p-4">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-sm text-yellow-400 icon-text">
              <span class="text-sm">⊞</span>
              <span>MISSION QUEUE</span>
            </h2>
            <div class="flex gap-2">
              <button
                phx-click="toggle_auto_start"
                class={"arcade-btn text-[8px] py-1 px-2 #{if @auto_start_queue, do: "border-green-500 text-green-400", else: "border-cyan-700 text-cyan-600"}"}
              >
                {if @auto_start_queue, do: "AUTO ●", else: "AUTO ○"}
              </button>
              <.link
                patch={~p"/missions/new"}
                class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
              >
                + NEW
              </.link>
            </div>
          </div>

          <%= if Enum.empty?(@pending_missions) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- QUEUE EMPTY -</p>
          <% else %>
            <div class="space-y-2">
              <%= for {mission, idx} <- Enum.with_index(@pending_missions) do %>
                <div class="border border-yellow-700 p-2 flex justify-between items-center hover:bg-yellow-900/10 transition-colors">
                  <.link patch={~p"/missions/#{mission.id}"} class="flex items-center gap-3 flex-1">
                    <span class="text-yellow-500 text-xs">{idx + 1}.</span>
                    <div>
                      <div class="text-white text-xs flex items-center gap-2">
                        {mission.sprite.name}
                        <%= if mission.schedule_enabled do %>
                          <span
                            class="text-[8px] text-fuchsia-400"
                            title={schedule_description(mission)}
                          >
                            ⏰
                          </span>
                        <% end %>
                      </div>
                      <div class="text-[8px] text-cyan-600">
                        MAX {mission.max_waves} WAVES
                        <%= if mission.schedule_enabled && mission.next_run_at do %>
                          <span class="text-fuchsia-400 ml-2">
                            NEXT: {format_relative_time(mission.next_run_at)}
                          </span>
                        <% end %>
                      </div>
                    </div>
                  </.link>
                  <div class="flex gap-2">
                    <.link
                      patch={~p"/missions/#{mission.id}/edit"}
                      class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
                    >
                      EDIT
                    </.link>
                    <button
                      phx-click="start_mission"
                      phx-value-id={mission.id}
                      class="arcade-btn border-green-500 text-green-400 text-[8px] py-1 px-2"
                    >
                      START
                    </button>
                    <button
                      phx-click="delete_mission"
                      phx-value-id={mission.id}
                      data-confirm="Delete this mission?"
                      class="arcade-btn border-red-500 text-red-400 text-[8px] py-1 px-2"
                    >
                      ✕
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>
        
    <!-- Recent Saves -->
        <section class="arcade-panel p-4">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-sm text-cyan-400 icon-text">
              <span class="text-sm">◈</span>
              <span>CHECKPOINTS</span>
            </h2>
          </div>

          <%= if Enum.empty?(@recent_saves) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- NO SAVES -</p>
          <% else %>
            <div class="space-y-2 max-h-64 overflow-y-auto">
              <%= for save <- @recent_saves do %>
                <div class="border border-cyan-800 p-2 flex justify-between items-center hover:bg-cyan-900/10 transition-colors">
                  <.link patch={~p"/saves/#{save.id}"} class="flex-1 cursor-pointer">
                    <div class="text-white text-xs">{save.sprite.name}</div>
                    <div class="text-[8px] text-cyan-600">
                      {save.comment || "WAVE-#{save.wave_number}"}
                    </div>
                  </.link>
                  <button
                    phx-click="restore_save"
                    phx-value-id={save.id}
                    class="arcade-btn border-green-500 text-green-400 text-[8px] py-1 px-2"
                  >
                    LOAD
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>
        
    <!-- High Scores (Completed) -->
        <section class="arcade-panel p-4">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-sm text-fuchsia-400 icon-text">
              <span class="text-sm">★</span>
              <span>HIGH SCORES</span>
            </h2>
          </div>

          <%= if Enum.empty?(@completed_missions) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- NO SCORES -</p>
          <% else %>
            <div class="space-y-2 max-h-64 overflow-y-auto">
              <%= for mission <- @completed_missions do %>
                <.link
                  patch={~p"/missions/#{mission.id}"}
                  class={"border p-2 flex justify-between items-center hover:bg-white/5 cursor-pointer block #{status_border_class(mission.status)}"}
                >
                  <div>
                    <div class={"text-xs #{status_text_class(mission.status)} flex items-center gap-2"}>
                      {mission.sprite.name}
                      <%= if mission.schedule_enabled do %>
                        <span
                          class="text-[8px] text-fuchsia-400"
                          title={schedule_description(mission)}
                        >
                          ⏰
                        </span>
                      <% end %>
                    </div>
                    <div class="text-[8px] text-cyan-600">
                      {length(mission.waves)} WAVES • {status_label(mission.status)}
                      <%= if mission.schedule_enabled && mission.next_run_at do %>
                        <span class="text-fuchsia-400 ml-1">
                          → {format_relative_time(mission.next_run_at)}
                        </span>
                      <% end %>
                    </div>
                  </div>
                  <div class="text-[10px] text-white">
                    {format_duration(mission.started_at, mission.finished_at)}
                  </div>
                </.link>
              <% end %>
            </div>
          <% end %>
        </section>
      </div>
      
    <!-- Sprites Status -->
      <section class="arcade-panel p-4 mt-4">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-sm text-white icon-text">
            <span class="text-sm">◆</span>
            <span>FLEET STATUS</span>
          </h2>
          <div class="flex gap-2">
            <button
              phx-click="sync_sprites"
              class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
            >
              SYNC
            </button>
            <.link
              patch={~p"/sprites/new"}
              class="arcade-btn border-green-500 text-green-400 text-[8px] py-1 px-2"
            >
              + ADD
            </.link>
          </div>
        </div>
        <div class="flex flex-wrap gap-3">
          <%= for sprite <- @sprites do %>
            <.link
              patch={~p"/sprites/#{sprite.id}"}
              class={"border-2 px-3 py-2 flex items-center gap-2 hover:bg-white/5 cursor-pointer transition-colors #{sprite_status_class(sprite.status)}"}
            >
              <span class={"text-lg #{sprite_indicator_class(sprite.status)}"}>◆</span>
              <span class="text-white text-xs">{sprite.name}</span>
            </.link>
          <% end %>
        </div>
      </section>
      
    <!-- Bottom Decoration -->
      <div class="mt-6 flex justify-center">
        <div class="flex items-center gap-4 text-[10px] text-cyan-600">
          <span>▂▂▂</span>
          <span class="text-green-500">SHIELDS</span>
          <span>▂▂▂</span>
          <span>▂▂▂</span>
          <span class="text-green-500">ACTIVE</span>
          <span>▂▂▂</span>
        </div>
      </div>
      
    <!-- Credit Insert -->
      <div class="text-center mt-4 text-[8px] text-cyan-700" aria-hidden="true">
        CREDIT 01
      </div>
    </main>
    """
  end

  defp status_border_class(:completed), do: "border-cyan-500"
  defp status_border_class(:failed), do: "border-red-500"
  defp status_border_class(:aborted), do: "border-yellow-500"
  defp status_border_class(_), do: "border-cyan-500"

  defp status_text_class(:completed), do: "text-cyan-400 status-completed"
  defp status_text_class(:failed), do: "text-red-400 status-failed"
  defp status_text_class(:aborted), do: "text-yellow-400 status-aborted"
  defp status_text_class(_), do: "text-cyan-400"

  defp status_label(:completed), do: "VICTORY"
  defp status_label(:failed), do: "DESTROYED"
  defp status_label(:aborted), do: "RETREAT"
  defp status_label(status), do: status |> to_string() |> String.upcase()

  defp sprite_status_class(:available), do: "border-green-500"
  defp sprite_status_class(:busy), do: "border-yellow-500"
  defp sprite_status_class(:offline), do: "border-red-500"
  defp sprite_status_class(_), do: "border-cyan-800"

  defp sprite_indicator_class(:available), do: "text-green-400 status-running"
  defp sprite_indicator_class(:busy), do: "text-yellow-400 blink status-pending"
  defp sprite_indicator_class(:offline), do: "text-red-400 status-failed"
  defp sprite_indicator_class(_), do: "text-cyan-600"

  defp format_duration(nil, _), do: "-"
  defp format_duration(_, nil), do: "-"

  defp format_duration(started_at, finished_at) do
    diff = DateTime.diff(finished_at, started_at, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      true -> "#{div(diff, 3600)}h #{rem(div(diff, 60), 60)}m"
    end
  end

  defp format_datetime(datetime), do: TimezoneHelper.format_datetime(datetime)

  defp schedule_description(mission) do
    Invader.Missions.ScheduleCalculator.describe(mission)
  end

  defp format_relative_time(nil), do: "-"

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(datetime, now, :second)

    cond do
      diff < 0 -> "now"
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86400)}d"
    end
  end
end
