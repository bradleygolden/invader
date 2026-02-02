defmodule InvaderWeb.DashboardLive do
  @moduledoc """
  8-bit Space Invaders themed dashboard for monitoring agent missions.
  """
  use InvaderWeb, :live_view

  alias Invader.Missions
  alias Invader.Sprites
  alias Invader.Saves
  alias Invader.Campaigns
  alias InvaderWeb.TimezoneHelper

  require Ash.Query

  @refresh_interval 5000
  @scores_per_page 10

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
      Phoenix.PubSub.subscribe(Invader.PubSub, "missions")
      Phoenix.PubSub.subscribe(Invader.PubSub, "settings")
      Phoenix.PubSub.subscribe(Invader.PubSub, "sprites:updates")
    end

    socket =
      socket
      |> assign(:page_title, "Invader Dashboard")
      |> assign(:auto_start_queue, Invader.Settings.auto_start_queue?())
      |> assign(:timezone_mode, Invader.Settings.timezone_mode())
      |> assign(:time_format, Invader.Settings.time_format())
      |> assign(:scores_page, 1)
      |> assign(:scores_per_page, @scores_per_page)
      |> assign(:show_profile_menu, false)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    page = parse_page(params["page"])

    socket
    |> assign(:page_title, "Invader Dashboard")
    |> assign(:sprite, nil)
    |> assign(:mission, nil)
    |> assign(:save, nil)
    |> assign(:scores_page, page)
    |> load_data()
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
        checkpoints = Saves.Save.for_mission!(mission.id)

        # Subscribe to running wave's output if mission is running
        socket = maybe_subscribe_to_wave(socket, mission)

        socket
        |> assign(:page_title, "Mission Details")
        |> assign(:mission, mission)
        |> assign(:mission_checkpoints, checkpoints)

      _ ->
        socket
        |> put_flash(:error, "Mission not found")
        |> push_patch(to: ~p"/")
    end
  end

  defp apply_action(socket, :settings, _params) do
    socket
    |> assign(:page_title, "Settings")
  end

  defp apply_action(socket, :loadouts, _params) do
    socket
    |> assign(:page_title, "Loadouts")
  end

  defp apply_action(socket, :connections, _params) do
    socket
    |> assign(:page_title, "Connections")
    |> assign(:add_connection_type, nil)
  end

  defp apply_action(socket, :add_connection, %{"type" => type}) do
    socket
    |> assign(:page_title, "Add Connection")
    |> assign(:add_connection_type, type)
  end

  defp parse_page(nil), do: 1

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp maybe_subscribe_to_wave(socket, mission) do
    # Unsubscribe from previous wave if any
    if socket.assigns[:subscribed_wave_topic] do
      Phoenix.PubSub.unsubscribe(Invader.PubSub, socket.assigns.subscribed_wave_topic)
    end

    # Find running wave and subscribe
    running_wave = Enum.find(mission.waves, &is_nil(&1.exit_code))

    if running_wave && connected?(socket) do
      topic = "wave:#{running_wave.id}"
      Phoenix.PubSub.subscribe(Invader.PubSub, topic)
      assign(socket, :subscribed_wave_topic, topic)
    else
      assign(socket, :subscribed_wave_topic, nil)
    end
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
  def handle_info({:wave_output, chunk}, socket) do
    # Forward output chunk to MissionDetailComponent
    if socket.assigns[:mission] do
      send_update(InvaderWeb.MissionDetailComponent,
        id: socket.assigns.mission.id,
        live_output_chunk: chunk
      )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:open_loadouts_modal}, socket) do
    {:noreply, push_patch(socket, to: ~p"/loadouts")}
  end

  @impl true
  def handle_info({:sprites_synced, _sprites}, socket) do
    {:noreply, load_data(socket)}
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
          {:ok, _} ->
            # Kill the running process immediately
            Invader.SpriteCli.Cli.kill_mission(id)
            {:noreply, load_data(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Mission cannot be paused")}
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
          {:ok, _} ->
            # Kill the running process immediately
            Invader.SpriteCli.Cli.kill_mission(id)
            {:noreply, load_data(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Mission cannot be aborted")}
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
        # Delete from sprites.dev first, then from local database
        case Invader.SpriteCli.Cli.destroy(sprite.name) do
          :ok ->
            Ash.destroy!(sprite)

            {:noreply,
             socket
             |> put_flash(:info, "Sprite deleted")
             |> load_data()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to delete sprite: #{inspect(reason)}")}
        end

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
        mission_id = save.mission_id
        Ash.destroy!(save)

        # Reload checkpoints if we're viewing this mission
        socket =
          if socket.assigns[:mission] && socket.assigns.mission.id == mission_id do
            checkpoints = Saves.Save.for_mission!(mission_id)
            assign(socket, :mission_checkpoints, checkpoints)
          else
            socket
          end

        {:noreply, put_flash(socket, :info, "Checkpoint deleted")}

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

  @impl true
  def handle_event("toggle_profile_menu", _params, socket) do
    {:noreply, assign(socket, :show_profile_menu, !socket.assigns.show_profile_menu)}
  end

  @impl true
  def handle_event("close_profile_menu", _params, socket) do
    {:noreply, assign(socket, :show_profile_menu, false)}
  end

  @impl true
  def handle_event("scores_page", %{"page" => page}, socket) do
    page = String.to_integer(page)
    total_pages = socket.assigns.scores_total_pages

    page = max(1, min(page, total_pages))

    socket =
      socket
      |> assign(:scores_page, page)
      |> load_data()

    {:noreply, socket}
  end

  defp load_data(socket) do
    # Load all missions for running/pending (these are small lists)
    all_missions = Missions.Mission.list!() |> Ash.load!([:sprite, :waves])
    sprites = Sprites.Sprite.list!()

    running = Enum.filter(all_missions, &(&1.status in [:running, :pausing, :paused]))

    pending =
      all_missions
      |> Enum.filter(&(&1.status == :pending))
      |> Enum.sort_by(& &1.priority, :desc)

    # Load completed missions with pagination using Ash's native support
    page = socket.assigns[:scores_page] || 1
    per_page = socket.assigns[:scores_per_page] || @scores_per_page
    offset = (page - 1) * per_page

    completed_statuses = [:completed, :failed, :aborted]

    completed_page =
      Missions.Mission
      |> Ash.Query.filter(status: [in: completed_statuses])
      |> Ash.Query.sort(finished_at: :desc)
      |> Ash.Query.load([:sprite, :waves])
      |> Ash.read!(page: [limit: per_page, offset: offset, count: true])

    # Calculate total pages
    total_completed = completed_page.count || 0
    total_pages = max(1, ceil(total_completed / per_page))

    # Ensure current page is valid
    page = min(page, total_pages)

    # Check if Sprites connection is configured
    has_sprites_connection =
      case Invader.Connections.Connection.get_by_type(:sprites) do
        {:ok, _} -> true
        _ -> false
      end

    # Load active campaigns
    campaigns =
      Campaigns.Campaign.list!()
      |> Ash.load!([:nodes, :runs])
      |> Enum.filter(&(&1.status in [:draft, :active]))
      |> Enum.take(5)

    socket
    |> assign(:running_missions, running)
    |> assign(:pending_missions, pending)
    |> assign(:completed_missions, completed_page.results)
    |> assign(:scores_page, page)
    |> assign(:scores_total_pages, total_pages)
    |> assign(:scores_total_count, total_completed)
    |> assign(:sprites, sprites)
    |> assign(:stats, calculate_stats(all_missions))
    |> assign(:has_sprites_connection, has_sprites_connection)
    |> assign(:campaigns, campaigns)
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
      class="arcade-container min-h-screen bg-black p-2 sm:p-4 relative z-10"
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
          checkpoints={@mission_checkpoints}
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

      <.modal :if={@live_action == :settings} id="settings-modal" show on_cancel={JS.patch(~p"/")}>
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

      <.modal :if={@live_action == :loadouts} id="loadouts-modal" show on_cancel={JS.patch(~p"/")}>
        <:title>LOADOUTS</:title>
        <.live_component
          module={InvaderWeb.LoadoutsComponent}
          id="loadouts-manager"
        />
      </.modal>

      <.modal
        :if={@live_action in [:connections, :add_connection]}
        id="connections-modal"
        show
        on_cancel={JS.patch(~p"/")}
      >
        <:title>
          {if @live_action == :add_connection, do: "ADD CONNECTION", else: "CONNECTIONS"}
        </:title>
        <.live_component
          module={InvaderWeb.ConnectionsComponent}
          id="connections-manager"
          add_connection_type={assigns[:add_connection_type]}
        />
      </.modal>
      
    <!-- Animated Aliens Header Decoration -->
      <div class="hidden sm:flex justify-center gap-4 mb-2 text-2xl">
        <span class="alien-sprite text-cyan-400"></span>
        <span class="alien-sprite text-magenta-400" style="animation-delay: 0.2s;"></span>
        <span class="alien-sprite text-green-400" style="animation-delay: 0.4s;"></span>
        <span class="alien-sprite text-cyan-400" style="animation-delay: 0.6s;"></span>
        <span class="alien-sprite text-magenta-400" style="animation-delay: 0.8s;"></span>
      </div>
      
    <!-- Header -->
      <header class="text-center mb-4 sm:mb-6 relative">
        <div class="absolute right-0 top-0 flex gap-1">
          <button
            id="audio-toggle"
            phx-hook="ArcadeAudio"
            class="arcade-btn border-cyan-700 text-cyan-500 p-1.5 hover:border-cyan-400 hover:text-cyan-400"
            title="Toggle Music"
          >
            <!-- Sound On Icon (speaker with waves) -->
            <svg
              viewBox="0 0 16 16"
              class="w-5 h-5 fill-current sound-on"
              style="image-rendering: pixelated;"
            >
              <rect x="0" y="5" width="2" height="6" />
              <rect x="2" y="4" width="2" height="8" />
              <rect x="4" y="3" width="2" height="10" />
              <rect x="6" y="2" width="2" height="12" />
              <rect x="10" y="4" width="2" height="2" />
              <rect x="10" y="10" width="2" height="2" />
              <rect x="12" y="6" width="2" height="4" />
            </svg>
            <!-- Sound Off Icon (speaker with X) -->
            <svg
              viewBox="0 0 16 16"
              class="w-5 h-5 fill-current sound-off hidden"
              style="image-rendering: pixelated;"
            >
              <rect x="0" y="5" width="2" height="6" />
              <rect x="2" y="4" width="2" height="8" />
              <rect x="4" y="3" width="2" height="10" />
              <rect x="6" y="2" width="2" height="12" />
              <rect x="10" y="4" width="2" height="2" class="fill-red-500" />
              <rect x="14" y="4" width="2" height="2" class="fill-red-500" />
              <rect x="11" y="5" width="2" height="2" class="fill-red-500" />
              <rect x="13" y="5" width="2" height="2" class="fill-red-500" />
              <rect x="12" y="6" width="2" height="4" class="fill-red-500" />
              <rect x="11" y="9" width="2" height="2" class="fill-red-500" />
              <rect x="13" y="9" width="2" height="2" class="fill-red-500" />
              <rect x="10" y="10" width="2" height="2" class="fill-red-500" />
              <rect x="14" y="10" width="2" height="2" class="fill-red-500" />
            </svg>
          </button>
          <.link
            patch={~p"/connections"}
            class="arcade-btn border-cyan-700 text-cyan-500 p-1.5 hover:border-cyan-400 hover:text-cyan-400"
            title="Connections"
          >
            <svg
              viewBox="0 0 16 16"
              class="w-5 h-5 fill-current"
              style="image-rendering: pixelated;"
            >
              <rect x="0" y="6" width="4" height="4" />
              <rect x="4" y="7" width="3" height="2" />
              <rect x="9" y="7" width="3" height="2" />
              <rect x="12" y="6" width="4" height="4" />
              <rect x="7" y="4" width="2" height="2" />
              <rect x="7" y="10" width="2" height="2" />
            </svg>
          </.link>
          <!-- Profile Dropdown -->
          <div class="relative">
            <button
              phx-click="toggle_profile_menu"
              class={"arcade-btn p-1.5 hover:border-cyan-400 hover:text-cyan-400 " <> if(@show_profile_menu, do: "border-cyan-400 text-cyan-400", else: "border-cyan-700 text-cyan-500")}
              title="Profile"
            >
              <!-- Player/Profile Icon (8-bit style person) -->
              <svg
                viewBox="0 0 16 16"
                class="w-5 h-5 fill-current"
                style="image-rendering: pixelated;"
              >
                <rect x="5" y="1" width="6" height="6" />
                <rect x="6" y="3" width="1" height="2" class="fill-black" />
                <rect x="9" y="3" width="1" height="2" class="fill-black" />
                <rect x="3" y="8" width="10" height="2" />
                <rect x="5" y="10" width="6" height="4" />
                <rect x="4" y="14" width="3" height="2" />
                <rect x="9" y="14" width="3" height="2" />
              </svg>
            </button>
            <!-- Dropdown Menu -->
            <div
              :if={@show_profile_menu}
              phx-click-away="close_profile_menu"
              class="absolute right-0 top-full mt-1 w-56 bg-black border border-cyan-700 p-0 z-50"
            >
              <div class="p-3 border-b border-cyan-800 bg-black">
                <div class="text-[8px] text-cyan-700 uppercase tracking-wider">Signed in as</div>
                <div class="text-cyan-400 text-[10px] truncate mt-1">
                  {@current_user.name || @current_user.email}
                </div>
              </div>
              <div class="p-1 bg-black">
                <.link
                  patch={~p"/settings"}
                  phx-click={JS.push("close_profile_menu")}
                  class="flex items-center w-full text-left px-3 py-2 text-[10px] text-cyan-500 hover:bg-cyan-900/50 hover:text-cyan-400 transition-colors"
                >
                  <!-- 8-bit Gear Icon -->
                  <svg
                    viewBox="0 0 16 16"
                    class="w-4 h-4 fill-current mr-2"
                    style="image-rendering: pixelated;"
                  >
                    <rect x="6" y="0" width="4" height="2" />
                    <rect x="6" y="14" width="4" height="2" />
                    <rect x="0" y="6" width="2" height="4" />
                    <rect x="14" y="6" width="2" height="4" />
                    <rect x="2" y="2" width="2" height="2" />
                    <rect x="12" y="2" width="2" height="2" />
                    <rect x="2" y="12" width="2" height="2" />
                    <rect x="12" y="12" width="2" height="2" />
                    <rect x="4" y="4" width="8" height="8" />
                    <rect x="6" y="6" width="4" height="4" class="fill-black" />
                  </svg>
                  SETTINGS
                </.link>
                <.link
                  href={~p"/sign-out"}
                  class="flex items-center w-full text-left px-3 py-2 text-[10px] text-red-500 hover:bg-red-900/50 hover:text-red-400 transition-colors"
                >
                  <!-- 8-bit Power Icon -->
                  <svg
                    viewBox="0 0 16 16"
                    class="w-4 h-4 fill-current mr-2"
                    style="image-rendering: pixelated;"
                  >
                    <rect x="7" y="1" width="2" height="6" />
                    <rect x="4" y="3" width="2" height="2" />
                    <rect x="10" y="3" width="2" height="2" />
                    <rect x="2" y="5" width="2" height="4" />
                    <rect x="12" y="5" width="2" height="4" />
                    <rect x="2" y="9" width="2" height="2" />
                    <rect x="12" y="9" width="2" height="2" />
                    <rect x="4" y="11" width="2" height="2" />
                    <rect x="10" y="11" width="2" height="2" />
                    <rect x="6" y="13" width="4" height="2" />
                  </svg>
                  SIGN OUT
                </.link>
              </div>
            </div>
          </div>
        </div>
        <h1 class="text-3xl md:text-4xl font-bold tracking-widest arcade-glow">
          INVADER
        </h1>
        <p class="text-cyan-500 text-[10px] mt-3 tracking-wider">[ COMMAND CENTER ]</p>
      </header>
      
    <!-- Score Display - Classic Arcade Style -->
      <div class="flex justify-between items-start mb-4 sm:mb-6 px-1 sm:px-2">
        <div class="text-left">
          <div class="text-[8px] sm:text-[10px] text-white mb-1">SCORE&lt;1&gt;</div>
          <div class="text-base sm:text-xl text-white score-display">
            {String.pad_leading(to_string(@stats.completed * 100), 5, "0")}
          </div>
        </div>
        <div class="text-center">
          <div class="text-[8px] sm:text-[10px] text-red-500 mb-1">HI-SCORE</div>
          <div class="text-base sm:text-xl text-white score-display">
            {String.pad_leading(to_string(@stats.total_waves * 10), 5, "0")}
          </div>
        </div>
        <div class="text-right">
          <div class="text-[8px] sm:text-[10px] text-white mb-1">SCORE&lt;2&gt;</div>
          <div class="text-base sm:text-xl text-white score-display">
            {String.pad_leading(to_string(@stats.total * 50), 5, "0")}
          </div>
        </div>
      </div>
      
    <!-- Stats Bar -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 sm:gap-3 mb-6 text-center">
        <div class="arcade-panel p-2 sm:p-3">
          <div class="text-xl sm:text-2xl text-white">{@stats.total}</div>
          <div class="text-[8px] text-cyan-500 mt-1">MISSIONS</div>
        </div>
        <div class="arcade-panel p-2 sm:p-3">
          <div class="text-xl sm:text-2xl text-green-400">{@stats.completed}</div>
          <div class="text-[8px] text-cyan-500 mt-1">COMPLETED</div>
        </div>
        <div class="arcade-panel p-2 sm:p-3">
          <div class="text-xl sm:text-2xl text-red-500">{@stats.failed}</div>
          <div class="text-[8px] text-cyan-500 mt-1">DESTROYED</div>
        </div>
        <div class="arcade-panel p-2 sm:p-3">
          <div class="text-xl sm:text-2xl text-yellow-400">{@stats.total_waves}</div>
          <div class="text-[8px] text-cyan-500 mt-1">WAVES</div>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-3 sm:gap-4">
        <!-- Active Missions -->
        <section class="arcade-panel p-3 sm:p-4">
          <div class="flex justify-between items-center mb-3 sm:mb-4">
            <h2 class="text-xs sm:text-sm text-green-400 icon-text">
              <span class="text-xs sm:text-sm">▶</span>
              <span>ACTIVE INVASION</span>
            </h2>
          </div>

          <%= if Enum.empty?(@running_missions) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- AWAITING ORDERS -</p>
          <% else %>
            <div class="space-y-3 max-h-48 overflow-y-auto arcade-scroll">
              <%= for mission <- @running_missions do %>
                <div class={[
                  "border-2 p-3 bg-black/50 transition-colors",
                  mission.status == :paused && "border-yellow-500 hover:bg-yellow-900/20",
                  mission.status in [:running, :pausing] && "border-green-500 hover:bg-green-900/20"
                ]}>
                  <div class="flex justify-between items-start">
                    <.link
                      patch={~p"/missions/#{mission.id}"}
                      class="flex-1 cursor-pointer"
                    >
                      <div class="text-white text-xs">
                        <%= if mission.status == :paused do %>
                          <span class="text-yellow-400 mr-2">▌▌</span>
                        <% else %>
                          <span class="text-green-400 mr-2">▸</span>
                        <% end %>
                        {mission.sprite.name}
                        <%= if mission.status == :paused do %>
                          <span class="text-yellow-500 text-[8px] ml-2">PAUSED</span>
                        <% end %>
                      </div>
                      <div class="text-[10px] text-cyan-400 mt-1">
                        WAVE {mission.current_wave}/{mission.max_waves}
                      </div>
                      <div class="text-[8px] text-cyan-700 truncate max-w-xs mt-1">
                        {prompt_display(mission)}
                      </div>
                    </.link>
                    <div class="flex gap-1 sm:gap-2 flex-shrink-0">
                      <%= cond do %>
                        <% mission.status == :paused -> %>
                          <button
                            phx-click="resume_mission"
                            phx-value-id={mission.id}
                            class="arcade-btn border-green-500 text-green-400 text-[8px] py-1.5 px-1.5 sm:py-1 sm:px-2"
                          >
                            RESUME
                          </button>
                        <% mission.status == :pausing -> %>
                          <span class="arcade-btn border-yellow-500 text-yellow-400 text-[8px] py-1.5 px-1.5 sm:py-1 sm:px-2 opacity-70 animate-pulse cursor-not-allowed">
                            PAUSING...
                          </span>
                        <% true -> %>
                          <button
                            phx-click="pause_mission"
                            phx-value-id={mission.id}
                            class="arcade-btn border-yellow-500 text-yellow-400 text-[8px] py-1.5 px-1.5 sm:py-1 sm:px-2"
                          >
                            PAUSE
                          </button>
                      <% end %>
                      <button
                        phx-click="abort_mission"
                        phx-value-id={mission.id}
                        data-confirm="Are you sure you want to abort this mission? This action cannot be undone."
                        class="arcade-btn border-red-500 text-red-400 text-[8px] py-1.5 px-1.5 sm:py-1 sm:px-2"
                      >
                        ABORT
                      </button>
                    </div>
                  </div>
                  <!-- Progress bar -->
                  <.link patch={~p"/missions/#{mission.id}"} class="block">
                    <div class={[
                      "mt-3 h-2 bg-black border overflow-hidden cursor-pointer",
                      mission.status == :paused && "border-yellow-700",
                      mission.status in [:running, :pausing] && "border-green-700"
                    ]}>
                      <div
                        class={[
                          "h-full transition-all duration-500",
                          mission.status == :paused && "bg-yellow-500",
                          mission.status in [:running, :pausing] && "laser-progress"
                        ]}
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
        <section class="arcade-panel p-3 sm:p-4">
          <div class="flex justify-between items-center mb-3 sm:mb-4">
            <h2 class="text-xs sm:text-sm text-yellow-400 icon-text">
              <span class="text-xs sm:text-sm">⊞</span>
              <span>MISSION QUEUE</span>
            </h2>
            <div class="flex gap-1 sm:gap-2">
              <button
                phx-click="toggle_auto_start"
                class={"arcade-btn text-[8px] py-1.5 px-2 sm:py-1 sm:px-2 #{if @auto_start_queue, do: "border-green-500 text-green-400", else: "border-cyan-700 text-cyan-600"}"}
              >
                {if @auto_start_queue, do: "AUTO ●", else: "AUTO ○"}
              </button>
              <.link
                patch={~p"/missions/new"}
                class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1.5 px-2 sm:py-1 sm:px-2"
              >
                + NEW
              </.link>
            </div>
          </div>

          <%= if Enum.empty?(@pending_missions) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- QUEUE EMPTY -</p>
          <% else %>
            <div class="space-y-2 max-h-64 overflow-y-auto arcade-scroll">
              <%= for {mission, idx} <- Enum.with_index(@pending_missions) do %>
                <div class="border border-yellow-700 p-2 hover:bg-yellow-900/10 transition-colors">
                  <div class="flex justify-between items-start gap-2">
                    <.link
                      patch={~p"/missions/#{mission.id}"}
                      class="flex items-center gap-2 sm:gap-3 flex-1 min-w-0"
                    >
                      <span class="text-yellow-500 text-xs flex-shrink-0">{idx + 1}.</span>
                      <div class="min-w-0">
                        <div class="text-white text-xs flex items-center gap-2 truncate">
                          <span class="truncate">{mission.sprite.name}</span>
                          <%= if mission.schedule_enabled do %>
                            <span
                              class="text-[8px] text-fuchsia-400 flex-shrink-0"
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
                    <div class="flex gap-1 sm:gap-2 flex-shrink-0">
                      <.link
                        patch={~p"/missions/#{mission.id}/edit"}
                        class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1.5 px-1.5 sm:py-1 sm:px-2"
                      >
                        EDIT
                      </.link>
                      <button
                        phx-click="start_mission"
                        phx-value-id={mission.id}
                        class="arcade-btn border-green-500 text-green-400 text-[8px] py-1.5 px-1.5 sm:py-1 sm:px-2"
                      >
                        START
                      </button>
                      <button
                        phx-click="delete_mission"
                        phx-value-id={mission.id}
                        data-confirm="Delete this mission?"
                        class="arcade-btn border-red-500 text-red-400 text-[8px] py-1.5 px-1.5 sm:py-1 sm:px-2"
                      >
                        DEL
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>
        
    <!-- High Scores (Completed) -->
        <section class="arcade-panel p-3 sm:p-4 md:col-span-2">
          <div class="flex justify-between items-center mb-3 sm:mb-4">
            <h2 class="text-xs sm:text-sm text-fuchsia-400 icon-text">
              <span class="text-xs sm:text-sm">★</span>
              <span>HIGH SCORES</span>
            </h2>
            <%= if @scores_total_pages > 1 do %>
              <span class="text-[8px] text-fuchsia-400">
                {@scores_page}/{@scores_total_pages}
              </span>
            <% end %>
          </div>

          <%= if Enum.empty?(@completed_missions) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- NO SCORES -</p>
          <% else %>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
              <%= for mission <- @completed_missions do %>
                <.link
                  patch={~p"/missions/#{mission.id}"}
                  class={"border p-2 flex justify-between items-center hover:bg-white/5 cursor-pointer block #{status_border_class(mission.status)}"}
                >
                  <div class="min-w-0 flex-1">
                    <div class={"text-[10px] sm:text-xs #{status_text_class(mission.status)} flex items-center gap-2 truncate"}>
                      <span class="truncate">{mission.sprite.name}</span>
                      <%= if mission.schedule_enabled do %>
                        <span
                          class="text-[8px] text-fuchsia-400 flex-shrink-0"
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
                  <div class="text-right flex-shrink-0 ml-2">
                    <div class="text-[10px] text-white">{format_duration(mission)}</div>
                    <div class="text-[8px] text-cyan-700">{format_time_ago(mission.finished_at)}</div>
                  </div>
                </.link>
              <% end %>
            </div>
            
    <!-- Pagination Controls -->
            <%= if @scores_total_pages > 1 do %>
              <div class="flex justify-center items-center gap-1 mt-4 pt-3 border-t border-fuchsia-800">
                <button
                  phx-click="scores_page"
                  phx-value-page="1"
                  disabled={@scores_page == 1}
                  class={"arcade-btn py-1.5 px-2 #{if @scores_page == 1, do: "border-cyan-800 cursor-not-allowed", else: "border-fuchsia-500 hover:border-fuchsia-400"}"}
                  title="First page"
                >
                  <svg
                    viewBox="0 0 12 10"
                    class={"w-3 h-2.5 #{if @scores_page == 1, do: "fill-cyan-800", else: "fill-fuchsia-400"}"}
                    style="image-rendering: pixelated;"
                  >
                    <rect x="0" y="0" width="2" height="10" />
                    <rect x="4" y="4" width="2" height="2" />
                    <rect x="6" y="3" width="2" height="4" />
                    <rect x="8" y="2" width="2" height="6" />
                    <rect x="10" y="1" width="2" height="8" />
                  </svg>
                </button>
                <button
                  phx-click="scores_page"
                  phx-value-page={@scores_page - 1}
                  disabled={@scores_page == 1}
                  class={"arcade-btn py-1.5 px-2 #{if @scores_page == 1, do: "border-cyan-800 cursor-not-allowed", else: "border-fuchsia-500 hover:border-fuchsia-400"}"}
                  title="Previous page"
                >
                  <svg
                    viewBox="0 0 8 10"
                    class={"w-2 h-2.5 #{if @scores_page == 1, do: "fill-cyan-800", else: "fill-fuchsia-400"}"}
                    style="image-rendering: pixelated;"
                  >
                    <rect x="0" y="4" width="2" height="2" />
                    <rect x="2" y="3" width="2" height="4" />
                    <rect x="4" y="2" width="2" height="6" />
                    <rect x="6" y="1" width="2" height="8" />
                  </svg>
                </button>
                <span class="text-[10px] text-fuchsia-400 px-3 min-w-[80px] text-center">
                  PAGE {@scores_page}
                </span>
                <button
                  phx-click="scores_page"
                  phx-value-page={@scores_page + 1}
                  disabled={@scores_page == @scores_total_pages}
                  class={"arcade-btn py-1.5 px-2 #{if @scores_page == @scores_total_pages, do: "border-cyan-800 cursor-not-allowed", else: "border-fuchsia-500 hover:border-fuchsia-400"}"}
                  title="Next page"
                >
                  <svg
                    viewBox="0 0 8 10"
                    class={"w-2 h-2.5 #{if @scores_page == @scores_total_pages, do: "fill-cyan-800", else: "fill-fuchsia-400"}"}
                    style="image-rendering: pixelated;"
                  >
                    <rect x="0" y="1" width="2" height="8" />
                    <rect x="2" y="2" width="2" height="6" />
                    <rect x="4" y="3" width="2" height="4" />
                    <rect x="6" y="4" width="2" height="2" />
                  </svg>
                </button>
                <button
                  phx-click="scores_page"
                  phx-value-page={@scores_total_pages}
                  disabled={@scores_page == @scores_total_pages}
                  class={"arcade-btn py-1.5 px-2 #{if @scores_page == @scores_total_pages, do: "border-cyan-800 cursor-not-allowed", else: "border-fuchsia-500 hover:border-fuchsia-400"}"}
                  title="Last page"
                >
                  <svg
                    viewBox="0 0 12 10"
                    class={"w-3 h-2.5 #{if @scores_page == @scores_total_pages, do: "fill-cyan-800", else: "fill-fuchsia-400"}"}
                    style="image-rendering: pixelated;"
                  >
                    <rect x="0" y="1" width="2" height="8" />
                    <rect x="2" y="2" width="2" height="6" />
                    <rect x="4" y="3" width="2" height="4" />
                    <rect x="6" y="4" width="2" height="2" />
                    <rect x="10" y="0" width="2" height="10" />
                  </svg>
                </button>
              </div>
            <% end %>
          <% end %>
        </section>
      </div>
      
    <!-- Sprites Status -->
      <section class="arcade-panel p-3 sm:p-4 mt-3 sm:mt-4">
        <div class="flex justify-between items-center mb-3 sm:mb-4">
          <h2 class="text-xs sm:text-sm text-white icon-text">
            <span class="text-xs sm:text-sm">◆</span>
            <span>FLEET STATUS</span>
          </h2>
          <%= if @has_sprites_connection do %>
            <div class="flex gap-1 sm:gap-2">
              <button
                phx-click="sync_sprites"
                class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1.5 px-2 sm:py-1 sm:px-2"
              >
                SYNC
              </button>
              <.link
                patch={~p"/sprites/new"}
                class="arcade-btn border-green-500 text-green-400 text-[8px] py-1.5 px-2 sm:py-1 sm:px-2"
              >
                + ADD
              </.link>
            </div>
          <% end %>
        </div>
        <%= if @has_sprites_connection do %>
          <div class="flex flex-wrap gap-2 sm:gap-3">
            <%= for sprite <- @sprites do %>
              <.link
                patch={~p"/sprites/#{sprite.id}"}
                class={"border-2 px-2 py-1.5 sm:px-3 sm:py-2 hover:bg-white/5 transition-colors block cursor-pointer #{sprite_status_class(sprite.status)}"}
              >
                <div class="flex items-center gap-1.5 sm:gap-2">
                  <span class={"text-base sm:text-lg #{sprite_indicator_class(sprite.status)}"}>
                    ◆
                  </span>
                  <span class="text-white text-[10px] sm:text-xs">{sprite.name}</span>
                </div>
                <div class={"text-[8px] mt-1 #{sprite_status_text_class(sprite.status)}"}>
                  {sprite_status_label(sprite.status)}
                </div>
              </.link>
            <% end %>
          </div>
        <% else %>
          <div class="text-center py-6">
            <p class="text-cyan-600 text-[10px] mb-3">- SPRITES CONNECTION REQUIRED -</p>
            <p class="text-cyan-700 text-[8px] mb-4">
              Connect to Sprites to sync and manage your fleet
            </p>
            <.link
              patch={~p"/connections/add/sprites"}
              class="arcade-btn border-green-500 text-green-400 text-[10px] py-2 px-4 inline-flex items-center gap-2"
            >
              <.sprites_icon />
              <span>+ ADD SPRITES CONNECTION</span>
            </.link>
          </div>
        <% end %>
      </section>
      
    <!-- Campaigns Section -->
      <section class="arcade-panel p-3 sm:p-4 mt-3 sm:mt-4">
        <div class="flex justify-between items-center mb-3 sm:mb-4">
          <h2 class="text-xs sm:text-sm text-fuchsia-400 icon-text">
            <span class="text-xs sm:text-sm">⬡</span>
            <span>CAMPAIGNS</span>
          </h2>
          <div class="flex gap-1 sm:gap-2">
            <.link
              navigate={~p"/workflows"}
              class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1.5 px-2 sm:py-1 sm:px-2"
            >
              VIEW ALL
            </.link>
            <.link
              navigate={~p"/workflows/new"}
              class="arcade-btn border-green-500 text-green-400 text-[8px] py-1.5 px-2 sm:py-1 sm:px-2"
            >
              + NEW
            </.link>
          </div>
        </div>

        <%= if Enum.empty?(@campaigns) do %>
          <p class="text-cyan-600 text-center py-4 text-[10px]">- NO CAMPAIGNS -</p>
        <% else %>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            <%= for campaign <- @campaigns do %>
              <.link
                navigate={~p"/workflows/#{campaign.id}"}
                class={"border p-2 hover:bg-fuchsia-900/10 cursor-pointer block #{campaign_status_border(campaign.status)}"}
              >
                <div class="flex items-center justify-between">
                  <span class="text-white text-[10px] truncate">{campaign.name}</span>
                  <span class={"text-[8px] #{campaign_status_text(campaign.status)}"}>
                    {campaign_status_label(campaign.status)}
                  </span>
                </div>
                <div class="text-[8px] text-cyan-700 mt-1">
                  {length(campaign.nodes)} NODES
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </section>
      
    <!-- Bottom Decoration -->
      <div class="mt-4 sm:mt-6 flex justify-center">
        <div class="flex items-center gap-2 sm:gap-4 text-[8px] sm:text-[10px] text-cyan-600">
          <span>▂▂▂</span>
          <span class="text-green-500">SHIELDS</span>
          <span>▂▂▂</span>
          <span class="hidden sm:inline">▂▂▂</span>
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

  defp sprite_status_class(:available), do: "border-yellow-500"
  defp sprite_status_class(:busy), do: "border-green-500"
  defp sprite_status_class(:offline), do: "border-red-500"
  defp sprite_status_class(_), do: "border-cyan-800"

  defp sprite_indicator_class(:available), do: "text-yellow-400 status-pending"
  defp sprite_indicator_class(:busy), do: "text-green-400 blink status-running"
  defp sprite_indicator_class(:offline), do: "text-red-400 status-failed"
  defp sprite_indicator_class(_), do: "text-cyan-600"

  # 8-bit pixel art Sprites icon (Space Invader alien style)
  defp sprites_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 11 8" class="w-5 h-5 fill-current" style="image-rendering: pixelated;">
      <rect x="2" y="0" width="1" height="1" />
      <rect x="8" y="0" width="1" height="1" />
      <rect x="3" y="1" width="1" height="1" />
      <rect x="7" y="1" width="1" height="1" />
      <rect x="2" y="2" width="7" height="1" />
      <rect x="1" y="3" width="2" height="1" />
      <rect x="4" y="3" width="3" height="1" />
      <rect x="8" y="3" width="2" height="1" />
      <rect x="0" y="4" width="11" height="1" />
      <rect x="0" y="5" width="1" height="1" />
      <rect x="2" y="5" width="7" height="1" />
      <rect x="10" y="5" width="1" height="1" />
      <rect x="0" y="6" width="1" height="1" />
      <rect x="2" y="6" width="1" height="1" />
      <rect x="8" y="6" width="1" height="1" />
      <rect x="10" y="6" width="1" height="1" />
      <rect x="3" y="7" width="2" height="1" />
      <rect x="6" y="7" width="2" height="1" />
    </svg>
    """
  end

  defp sprite_status_text_class(:available), do: "text-yellow-400"
  defp sprite_status_text_class(:busy), do: "text-green-400"
  defp sprite_status_text_class(:offline), do: "text-red-400"
  defp sprite_status_text_class(_), do: "text-cyan-600"

  defp sprite_status_label(:available), do: "WARM"
  defp sprite_status_label(:busy), do: "BUSY"
  defp sprite_status_label(:offline), do: "COLD"
  defp sprite_status_label(_), do: "UNKNOWN"

  defp campaign_status_border(:draft), do: "border-yellow-500"
  defp campaign_status_border(:active), do: "border-green-500"
  defp campaign_status_border(:archived), do: "border-cyan-700"
  defp campaign_status_border(_), do: "border-fuchsia-500"

  defp campaign_status_text(:draft), do: "text-yellow-400"
  defp campaign_status_text(:active), do: "text-green-400"
  defp campaign_status_text(:archived), do: "text-cyan-600"
  defp campaign_status_text(_), do: "text-fuchsia-400"

  defp campaign_status_label(:draft), do: "DRAFT"
  defp campaign_status_label(:active), do: "ACTIVE"
  defp campaign_status_label(:archived), do: "ARCHIVED"
  defp campaign_status_label(status), do: status |> to_string() |> String.upcase()

  defp format_duration(%{waves: waves, status: status, finished_at: mission_finished_at})
       when is_list(waves) do
    # For terminal states, use mission's finished_at as upper bound for incomplete waves
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

    format_seconds(diff)
  end

  defp format_duration(_), do: "-"

  defp format_seconds(diff) do
    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      true -> "#{div(diff, 3600)}h #{rem(div(diff, 60), 60)}m"
    end
  end

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

  defp format_time_ago(nil), do: nil

  defp format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> "#{div(diff, 604_800)}w ago"
    end
  end
end
