defmodule InvaderWeb.SettingsLive do
  @moduledoc """
  LiveView for application settings.
  """
  use InvaderWeb, :live_view

  alias Invader.Settings
  alias InvaderWeb.TimezoneHelper

  import InvaderWeb.PageLayout

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Invader.PubSub, "settings")
    end

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:auto_start_queue, Settings.auto_start_queue?())
     |> assign(:timezone_mode, Settings.timezone_mode())
     |> assign(:time_format, Settings.time_format())}
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
  def handle_info({:settings_changed, :time_format, value}, socket) do
    {:noreply, assign(socket, :time_format, value)}
  end

  @impl true
  def handle_info({:settings_changed, _, _}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_timezone", _params, socket) do
    new_value = Settings.toggle_timezone_mode()
    {:noreply, assign(socket, :timezone_mode, new_value)}
  end

  @impl true
  def handle_event("toggle_time_format", _params, socket) do
    new_value = Settings.toggle_time_format()
    {:noreply, assign(socket, :time_format, new_value)}
  end

  @impl true
  def handle_event("toggle_auto_start", _params, socket) do
    new_value = Settings.toggle_auto_start_queue()
    {:noreply, assign(socket, :auto_start_queue, new_value)}
  end

  @impl true
  def handle_event("set_user_timezone", %{"timezone" => timezone}, socket) do
    Settings.set_user_timezone(timezone)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="settings-page" phx-hook="TimezoneDetector">
      <.arcade_page page_title="SETTINGS">
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
        </div>
      </.arcade_page>
    </div>
    """
  end
end
