defmodule InvaderWeb.SpriteDetailComponent do
  @moduledoc """
  LiveComponent for viewing sprite details including system metrics.
  """
  use InvaderWeb, :live_component

  alias Invader.SpriteCli.Cli

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Sprite Info -->
      <div class="grid grid-cols-2 gap-4 text-sm">
        <div>
          <span class="text-green-600">NAME</span>
          <div class="text-green-400 font-bold">{@sprite.name}</div>
        </div>
        <div>
          <span class="text-green-600">STATUS</span>
          <div class={status_class(@info[:status])}>
            {(@info[:status] || "unknown") |> to_string() |> String.upcase()}
          </div>
        </div>
        <div>
          <span class="text-green-600">ORGANIZATION</span>
          <div class="text-green-400">{@info[:organization] || @sprite.org || "-"}</div>
        </div>
        <div>
          <span class="text-green-600">VERSION</span>
          <div class="text-green-400">{@info[:version] || "-"}</div>
        </div>
        <%= if @info[:url] do %>
          <div class="col-span-2">
            <span class="text-green-600">URL</span>
            <div class="text-blue-400">
              <a href={@info[:url]} target="_blank" class="hover:underline">{@info[:url]}</a>
            </div>
          </div>
        <% end %>
      </div>
      
    <!-- System Metrics -->
      <%= if @metrics do %>
        <div class="border-t border-green-800 pt-4">
          <h3 class="text-green-400 font-bold mb-4 flex items-center gap-2">
            <span>📊</span>
            SYSTEM METRICS
            <button
              phx-click="refresh_metrics"
              phx-target={@myself}
              class="text-xs px-2 py-1 border border-green-700 rounded hover:bg-green-900/30"
              disabled={@loading}
            >
              {if @loading, do: "...", else: "↻ REFRESH"}
            </button>
          </h3>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <!-- CPU -->
            <div class="border border-green-800 rounded p-3 bg-black/50 overflow-hidden">
              <div class="text-green-600 text-xs mb-2">CPU</div>
              <div class="text-2xl text-green-400 font-bold">{@metrics.cpu.cores} cores</div>
              <div class="mt-2 text-xs">
                <div class="flex justify-between">
                  <span class="text-green-600">Load (1m)</span>
                  <span class={load_class(@metrics.cpu.load_1m, @metrics.cpu.cores)}>
                    {Float.round(@metrics.cpu.load_1m, 2)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-green-600">Load (5m)</span>
                  <span class="text-green-400">{Float.round(@metrics.cpu.load_5m, 2)}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-green-600">Load (15m)</span>
                  <span class="text-green-400">{Float.round(@metrics.cpu.load_15m, 2)}</span>
                </div>
              </div>
            </div>
            
    <!-- Memory -->
            <div class="border border-green-800 rounded p-3 bg-black/50 overflow-hidden">
              <div class="text-green-600 text-xs mb-2">MEMORY</div>
              <div class="text-2xl text-green-400 font-bold">
                {format_bytes(@metrics.memory.used)} / {format_bytes(@metrics.memory.total)}
              </div>
              <div class="mt-2">
                <div class="w-full bg-green-950 rounded-full h-2">
                  <div
                    class={memory_bar_class(@metrics.memory)}
                    style={"width: #{memory_percent(@metrics.memory)}%"}
                  >
                  </div>
                </div>
                <div class="text-xs text-green-600 mt-1">
                  {memory_percent(@metrics.memory)}% used
                </div>
              </div>
              <div class="mt-1 text-[10px] text-green-600 truncate">
                Avail: <span class="text-green-400">{format_bytes(@metrics.memory.available)}</span>
              </div>
            </div>
            
    <!-- Disk -->
            <div class="border border-green-800 rounded p-3 bg-black/50 overflow-hidden">
              <div class="text-green-600 text-xs mb-2">DISK</div>
              <div class="text-2xl text-green-400 font-bold">
                {format_bytes(@metrics.disk.used)} / {format_bytes(@metrics.disk.total)}
              </div>
              <div class="mt-2">
                <div class="w-full bg-green-950 rounded-full h-2">
                  <div
                    class={disk_bar_class(@metrics.disk.percent)}
                    style={"width: #{@metrics.disk.percent}%"}
                  >
                  </div>
                </div>
                <div class="text-xs text-green-600 mt-1">
                  {@metrics.disk.percent}% used
                </div>
              </div>
              <div class="mt-1 text-[10px] text-green-600 truncate">
                Avail: <span class="text-green-400">{format_bytes(@metrics.disk.available)}</span>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <div class="border-t border-green-800 pt-4">
          <div class="text-center py-8">
            <%= if @loading do %>
              <div class="text-green-600 animate-pulse">Loading metrics...</div>
            <% else %>
              <div class="text-green-700">
                <%= if @error do %>
                  <span class="text-red-500">Error: {@error}</span>
                <% else %>
                  Metrics not available
                <% end %>
              </div>
              <button
                phx-click="refresh_metrics"
                phx-target={@myself}
                class="mt-2 text-xs px-3 py-1 border border-green-700 rounded hover:bg-green-900/30"
              >
                Load Metrics
              </button>
            <% end %>
          </div>
        </div>
      <% end %>
      
    <!-- Actions -->
      <div class="flex justify-end gap-3 pt-4 border-t border-green-800">
        <button
          phx-hook="CopyToClipboard"
          id={"terminal-modal-#{@sprite.id}"}
          data-clipboard-text={"sprite console -o #{@sprite.org} -s #{@sprite.name}"}
          class="px-4 py-2 border border-cyan-600 text-cyan-400 rounded hover:bg-cyan-900/30"
          title="Copy terminal command to clipboard"
        >
          ⌨ TERM
        </button>
        <.link
          patch={~p"/"}
          class="px-4 py-2 border border-green-700 text-green-600 rounded hover:bg-green-900/30"
        >
          CLOSE
        </.link>
        <.link
          patch={~p"/sprites/#{@sprite.id}/edit"}
          class="px-4 py-2 border border-blue-600 text-blue-400 rounded hover:bg-blue-900/30"
        >
          EDIT
        </.link>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{sprite_metrics_loaded: metrics}, socket) do
    {:ok, assign(socket, loading: false, metrics: metrics, error: nil)}
  end

  def update(%{sprite_metrics_error: error}, socket) do
    {:ok, assign(socket, loading: false, error: error)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:metrics, fn -> nil end)
      |> assign_new(:info, fn -> %{} end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:error, fn -> nil end)

    # Load info and metrics on first render
    socket =
      if socket.assigns[:info] == %{} do
        load_sprite_data(socket)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh_metrics", _params, socket) do
    sprite = socket.assigns.sprite

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)

    send(self(), {:load_sprite_metrics, sprite.name, sprite.id})

    {:noreply, socket}
  end

  defp load_sprite_data(socket) do
    sprite = socket.assigns.sprite

    # Load info synchronously (it's quick)
    info =
      case Cli.get_info(sprite.name) do
        {:ok, info} -> info
        _ -> %{}
      end

    # Start async metrics loading - pass sprite id for send_update targeting
    send(self(), {:load_sprite_metrics, sprite.name, sprite.id})

    socket
    |> assign(:info, info)
    |> assign(:loading, true)
  end

  defp status_class("warm"), do: "text-green-400"
  defp status_class("running"), do: "text-green-400 animate-pulse"
  defp status_class("stopped"), do: "text-yellow-400"
  defp status_class(_), do: "text-green-600"

  defp load_class(load, cores) when load > cores, do: "text-red-400"
  defp load_class(load, cores) when load > cores * 0.7, do: "text-yellow-400"
  defp load_class(_, _), do: "text-green-400"

  defp memory_percent(%{total: 0}), do: 0
  defp memory_percent(%{used: used, total: total}), do: round(used / total * 100)

  defp memory_bar_class(memory) do
    percent = memory_percent(memory)

    cond do
      percent > 90 -> "bg-red-500 h-2 rounded-full transition-all"
      percent > 70 -> "bg-yellow-500 h-2 rounded-full transition-all"
      true -> "bg-green-500 h-2 rounded-full transition-all"
    end
  end

  defp disk_bar_class(percent) when percent > 90, do: "bg-red-500 h-2 rounded-full transition-all"

  defp disk_bar_class(percent) when percent > 70,
    do: "bg-yellow-500 h-2 rounded-full transition-all"

  defp disk_bar_class(_), do: "bg-green-500 h-2 rounded-full transition-all"

  defp format_bytes(bytes) when bytes >= 1_000_000_000_000 do
    "#{Float.round(bytes / 1_000_000_000_000, 1)} TB"
  end

  defp format_bytes(bytes) when bytes >= 1_000_000_000 do
    "#{Float.round(bytes / 1_000_000_000, 1)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_000_000 do
    "#{Float.round(bytes / 1_000_000, 1)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1_000 do
    "#{Float.round(bytes / 1_000, 1)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"
end
