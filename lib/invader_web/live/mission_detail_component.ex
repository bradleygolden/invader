defmodule InvaderWeb.MissionDetailComponent do
  @moduledoc """
  LiveComponent for viewing mission details including wave history.
  """
  use InvaderWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Mission Info -->
      <div class="grid grid-cols-2 gap-4 text-sm">
        <div>
          <span class="text-green-600">SPRITE</span>
          <div class="text-green-400">{@mission.sprite.name}</div>
        </div>
        <div>
          <span class="text-green-600">STATUS</span>
          <div class={status_text_class(@mission.status)}>
            {status_label(@mission.status)}
          </div>
        </div>
        <div>
          <span class="text-green-600">PROMPT</span>
          <div class="text-green-400 truncate" title={@mission.prompt_path || "inline"}>
            {prompt_display(@mission)}
          </div>
        </div>
        <div>
          <span class="text-green-600">PROGRESS</span>
          <div class="text-green-400">
            Wave {@mission.current_wave}/{@mission.max_waves}
          </div>
        </div>
        <div>
          <span class="text-green-600">PRIORITY</span>
          <div class="text-green-400">{@mission.priority}</div>
        </div>
        <div>
          <span class="text-green-600">DURATION</span>
          <div class="text-green-400">
            {format_duration(@mission.started_at, @mission.finished_at)}
          </div>
        </div>
      </div>

      <%= if @mission.error_message do %>
        <div class="border border-red-700 rounded p-3 bg-red-950/30">
          <span class="text-red-500 text-sm">ERROR</span>
          <div class="text-red-400 text-sm mt-1">{@mission.error_message}</div>
        </div>
      <% end %>
      
    <!-- Wave History -->
      <div>
        <h3 class="text-green-400 font-bold mb-3 flex items-center gap-2">
          <span>📊</span> WAVE HISTORY
        </h3>

        <%= if Enum.empty?(@mission.waves) do %>
          <p class="text-green-600 text-center py-4">NO WAVES RECORDED</p>
        <% else %>
          <div class="space-y-2 max-h-64 overflow-y-auto">
            <%= for wave <- Enum.sort_by(@mission.waves, & &1.number, :desc) do %>
              <div class="border border-green-800 rounded">
                <button
                  type="button"
                  phx-click="toggle_wave"
                  phx-value-wave-id={wave.id}
                  phx-target={@myself}
                  class="w-full p-2 flex justify-between items-center text-left hover:bg-green-950/30"
                >
                  <div class="flex items-center gap-3">
                    <span class="text-green-600">#{wave.number}</span>
                    <span class={exit_code_class(wave.exit_code)}>
                      {exit_code_label(wave.exit_code)}
                    </span>
                  </div>
                  <div class="flex items-center gap-3 text-xs text-green-700">
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
                  <div class="border-t border-green-800 p-2">
                    <%= if wave.output do %>
                      <pre class="text-xs text-green-500 bg-black p-2 rounded overflow-x-auto max-h-48 overflow-y-auto font-mono whitespace-pre-wrap">{wave.output}</pre>
                    <% else %>
                      <p class="text-green-700 text-xs">No output captured</p>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
      
    <!-- Actions -->
      <div class="flex justify-end gap-3 pt-4 border-t border-green-800">
        <.link
          patch={~p"/"}
          class="px-4 py-2 border border-green-700 text-green-600 rounded hover:bg-green-900/30"
        >
          CLOSE
        </.link>
        <%= if @mission.status == :pending do %>
          <.link
            patch={~p"/missions/#{@mission.id}/edit"}
            class="px-4 py-2 border border-blue-600 text-blue-400 rounded hover:bg-blue-900/30"
          >
            EDIT
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    mission = Ash.load!(assigns.mission, [:sprite, :waves])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:mission, mission)
     |> assign_new(:expanded_waves, fn -> MapSet.new() end)}
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

  defp prompt_display(%{prompt_path: path}) when is_binary(path), do: Path.basename(path)
  defp prompt_display(%{prompt: prompt}) when is_binary(prompt), do: "[inline]"
  defp prompt_display(_), do: "-"

  defp status_text_class(:completed), do: "text-green-400"
  defp status_text_class(:failed), do: "text-red-400"
  defp status_text_class(:aborted), do: "text-yellow-400"
  defp status_text_class(:running), do: "text-green-400 animate-pulse"
  defp status_text_class(:paused), do: "text-yellow-400"
  defp status_text_class(_), do: "text-green-400"

  defp status_label(status), do: status |> to_string() |> String.upcase()

  defp exit_code_class(nil), do: "text-green-600"
  defp exit_code_class(0), do: "text-green-400"
  defp exit_code_class(_), do: "text-red-400"

  defp exit_code_label(nil), do: "running..."
  defp exit_code_label(0), do: "OK"
  defp exit_code_label(code), do: "exit #{code}"

  defp format_duration(nil, _), do: "-"
  defp format_duration(_, nil), do: "in progress"

  defp format_duration(started_at, finished_at) do
    diff = DateTime.diff(finished_at, started_at, :second)

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
end
