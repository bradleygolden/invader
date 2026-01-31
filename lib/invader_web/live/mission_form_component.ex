defmodule InvaderWeb.MissionFormComponent do
  @moduledoc """
  LiveComponent for creating and editing missions.
  """
  use InvaderWeb, :live_component

  alias Invader.Missions.Mission
  alias Invader.Sprites.Sprite
  alias Invader.Settings
  alias InvaderWeb.TimezoneHelper

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.form
        for={@form}
        id="mission-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
        autocomplete="off"
        data-1p-ignore
        data-lpignore="true"
      >
        <!-- Sprite Selection -->
        <div :if={@action == :new} class="space-y-2">
          <label class="text-cyan-500 text-[10px] block">SELECT SPRITE</label>
          <select
            name={@form[:sprite_id].name}
            id={@form[:sprite_id].id}
            class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
            required
          >
            <option value="">-- SELECT --</option>
            <%= for {name, id} <- @sprite_options do %>
              <option value={id} selected={to_string(@form[:sprite_id].value) == to_string(id)}>
                {name}
              </option>
            <% end %>
          </select>
        </div>

        <div :if={@action == :edit} class="py-2 border-b border-cyan-800">
          <span class="text-cyan-500 text-[10px]">SPRITE</span>
          <div class="text-white mt-1">{@mission.sprite.name}</div>
        </div>
        
    <!-- Prompt Type Toggle -->
        <div class="space-y-3">
          <div class="flex gap-3">
            <button
              type="button"
              phx-click="set_prompt_mode"
              phx-value-mode="path"
              phx-target={@myself}
              class={"arcade-btn text-[8px] py-2 px-3 #{if @prompt_mode == :path, do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}
            >
              FILE PATH
            </button>
            <button
              type="button"
              phx-click="set_prompt_mode"
              phx-value-mode="inline"
              phx-target={@myself}
              class={"arcade-btn text-[8px] py-2 px-3 #{if @prompt_mode == :inline, do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}
            >
              INLINE
            </button>
          </div>

          <div :if={@prompt_mode == :path} class="space-y-2">
            <label class="text-cyan-500 text-[10px] block">PROMPT PATH</label>
            <input
              type="text"
              name={@form[:prompt_path].name}
              id={@form[:prompt_path].id}
              value={@form[:prompt_path].value}
              placeholder="/path/to/PROMPT.md"
              class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
            />
          </div>

          <div :if={@prompt_mode == :inline} class="space-y-2">
            <label class="text-cyan-500 text-[10px] block">PROMPT</label>
            <textarea
              name={@form[:prompt].name}
              id={@form[:prompt].id}
              placeholder="Enter your prompt..."
              rows="4"
              class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none resize-none"
            >{@form[:prompt].value}</textarea>
          </div>
        </div>
        
    <!-- Settings Grid -->
        <div class="grid grid-cols-2 gap-6">
          <div class="space-y-2">
            <label class="text-cyan-500 text-[10px] block">PRIORITY</label>
            <input
              type="number"
              name={@form[:priority].name}
              id={@form[:priority].id}
              value={@form[:priority].value}
              class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
            />
          </div>

          <div class="space-y-2">
            <label class="text-cyan-500 text-[10px] block">MAX WAVES</label>
            <input
              type="number"
              name={@form[:max_waves].name}
              id={@form[:max_waves].id}
              value={@form[:max_waves].value}
              class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
            />
          </div>
        </div>
        
    <!-- Duration -->
        <div class="space-y-2">
          <label class="text-cyan-500 text-[10px] block">MAX DURATION (SEC)</label>
          <input
            type="number"
            name={@form[:max_duration].name}
            id={@form[:max_duration].id}
            value={@form[:max_duration].value}
            placeholder="No limit"
            class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
          />
        </div>
        
    <!-- Scheduling Section -->
        <div class="space-y-4 pt-4 border-t border-cyan-800">
          <div class="flex items-center gap-3">
            <label class="text-cyan-500 text-[10px]">SCHEDULE</label>
            <label class="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                name={@form[:schedule_enabled].name}
                checked={@schedule_enabled}
                phx-click="toggle_schedule"
                phx-target={@myself}
                class="sr-only peer"
              />
              <div class="w-9 h-5 bg-gray-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-cyan-600">
              </div>
            </label>
          </div>

          <div :if={@schedule_enabled} class="space-y-4">
            <!-- Schedule Type -->
            <div class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">SCHEDULE TYPE</label>
              <select
                name={@form[:schedule_type].name}
                id={@form[:schedule_type].id}
                phx-change="change_schedule_type"
                phx-target={@myself}
                class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
              >
                <option value="">-- SELECT --</option>
                <option value="once" selected={@schedule_type == :once}>Once</option>
                <option value="hourly" selected={@schedule_type == :hourly}>Hourly</option>
                <option value="daily" selected={@schedule_type == :daily}>Daily</option>
                <option value="weekly" selected={@schedule_type == :weekly}>Weekly</option>
                <option value="custom" selected={@schedule_type == :custom}>Custom (Cron)</option>
              </select>
            </div>
            
    <!-- Once: DateTime Picker -->
            <div :if={@schedule_type == :once} class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">RUN AT ({timezone_label()})</label>
              <input
                type="datetime-local"
                name={@form[:next_run_at].name}
                id={@form[:next_run_at].id}
                value={format_datetime_for_input(@form[:next_run_at].value)}
                class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
              />
            </div>
            
    <!-- Hourly: Minute picker -->
            <div :if={@schedule_type == :hourly} class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">RUN AT MINUTE</label>
              <div class="flex items-center gap-2">
                <span class="text-cyan-600">Every hour at :</span>
                <input
                  type="text"
                  inputmode="numeric"
                  name={@form[:schedule_minute].name}
                  id={@form[:schedule_minute].id}
                  value={pad_number(@form[:schedule_minute].value, 0)}
                  maxlength="2"
                  pattern="[0-5]?[0-9]"
                  class="w-20 bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none text-center"
                />
              </div>
            </div>
            
    <!-- Daily: Time picker -->
            <div :if={@schedule_type == :daily} class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">RUN AT TIME ({timezone_label()})</label>
              <div class="flex items-center gap-2">
                <input
                  type="text"
                  inputmode="numeric"
                  name={@form[:schedule_hour].name}
                  id={@form[:schedule_hour].id}
                  value={format_hour_for_display(@form[:schedule_hour].value, 9)}
                  maxlength="2"
                  pattern={if is_12h_format?(), do: "1[0-2]|0?[1-9]", else: "[01]?[0-9]|2[0-3]"}
                  placeholder="HH"
                  class="w-20 bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none text-center"
                />
                <span class="text-cyan-600">:</span>
                <input
                  type="text"
                  inputmode="numeric"
                  name={@form[:schedule_minute].name}
                  id={@form[:schedule_minute].id}
                  value={pad_number(@form[:schedule_minute].value, 0)}
                  maxlength="2"
                  pattern="[0-5]?[0-9]"
                  placeholder="MM"
                  class="w-20 bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none text-center"
                />
                <select
                  :if={is_12h_format?()}
                  name="mission[schedule_ampm]"
                  class="bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                >
                  <option value="AM" selected={get_ampm(@form[:schedule_hour].value, 9) == "AM"}>
                    AM
                  </option>
                  <option value="PM" selected={get_ampm(@form[:schedule_hour].value, 9) == "PM"}>
                    PM
                  </option>
                </select>
              </div>
            </div>
            
    <!-- Weekly: Days + Time -->
            <div :if={@schedule_type == :weekly} class="space-y-4">
              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">DAYS</label>
                <div class="flex flex-wrap gap-2">
                  <%= for day <- ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] do %>
                    <label class={"arcade-btn text-[8px] py-2 px-3 cursor-pointer #{if day in (@schedule_days || []), do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}>
                      <input
                        type="checkbox"
                        name="mission[schedule_days][]"
                        value={day}
                        checked={day in (@schedule_days || [])}
                        phx-click="toggle_schedule_day"
                        phx-value-day={day}
                        phx-target={@myself}
                        class="sr-only"
                      />
                      {String.upcase(day)}
                    </label>
                  <% end %>
                </div>
              </div>
              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">AT TIME ({timezone_label()})</label>
                <div class="flex items-center gap-2">
                  <input
                    type="text"
                    inputmode="numeric"
                    name={@form[:schedule_hour].name}
                    id={@form[:schedule_hour].id}
                    value={format_hour_for_display(@form[:schedule_hour].value, 9)}
                    maxlength="2"
                    pattern={if is_12h_format?(), do: "1[0-2]|0?[1-9]", else: "[01]?[0-9]|2[0-3]"}
                    placeholder="HH"
                    class="w-20 bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none text-center"
                  />
                  <span class="text-cyan-600">:</span>
                  <input
                    type="text"
                    inputmode="numeric"
                    name={@form[:schedule_minute].name}
                    id={@form[:schedule_minute].id}
                    value={pad_number(@form[:schedule_minute].value, 0)}
                    maxlength="2"
                    pattern="[0-5]?[0-9]"
                    placeholder="MM"
                    class="w-20 bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none text-center"
                  />
                  <select
                    :if={is_12h_format?()}
                    name="mission[schedule_ampm]"
                    class="bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                  >
                    <option value="AM" selected={get_ampm(@form[:schedule_hour].value, 9) == "AM"}>
                      AM
                    </option>
                    <option value="PM" selected={get_ampm(@form[:schedule_hour].value, 9) == "PM"}>
                      PM
                    </option>
                  </select>
                </div>
              </div>
            </div>
            
    <!-- Custom: Cron expression -->
            <div :if={@schedule_type == :custom} class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">CRON EXPRESSION</label>
              <input
                type="text"
                name={@form[:schedule_cron].name}
                id={@form[:schedule_cron].id}
                value={@form[:schedule_cron].value}
                placeholder="* * * * *"
                class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none font-mono"
              />
              <p class="text-cyan-700 text-[8px]">
                Format: minute hour day-of-month month day-of-week
              </p>
            </div>
          </div>
        </div>
        
    <!-- Actions -->
        <div class="flex justify-end gap-4 pt-6 mt-6 border-t border-cyan-800">
          <.link
            patch={~p"/"}
            class="arcade-btn border-cyan-600 text-cyan-400 text-[10px]"
          >
            CANCEL
          </.link>
          <button
            type="submit"
            phx-disable-with="SAVING..."
            class="arcade-btn border-green-500 text-green-400 text-[10px]"
          >
            {(@action == :new && "CREATE") || "UPDATE"}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{mission: mission, action: action} = assigns, socket) do
    sprites = Sprite.list!()

    sprite_options =
      Enum.map(sprites, fn sprite ->
        {sprite.name, sprite.id}
      end)

    form =
      if action == :new do
        AshPhoenix.Form.for_create(Mission, :create, as: "mission")
      else
        mission = Ash.load!(mission, :sprite)
        AshPhoenix.Form.for_update(mission, :update, as: "mission")
      end

    # Determine initial mode based on existing data
    prompt_mode =
      cond do
        action == :new -> :inline
        mission.prompt && mission.prompt != "" -> :inline
        true -> :path
      end

    # Initialize scheduling state
    {schedule_enabled, schedule_type, schedule_days} =
      if action == :new do
        {false, nil, []}
      else
        {
          mission.schedule_enabled || false,
          mission.schedule_type,
          mission.schedule_days || []
        }
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:sprite_options, sprite_options)
     |> assign(:prompt_mode, prompt_mode)
     |> assign(:schedule_enabled, schedule_enabled)
     |> assign(:schedule_type, schedule_type)
     |> assign(:schedule_days, schedule_days)
     |> assign(:form, to_form(form))}
  end

  @impl true
  def handle_event("set_prompt_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :prompt_mode, String.to_existing_atom(mode))}
  end

  @impl true
  def handle_event("toggle_schedule", _params, socket) do
    new_enabled = !socket.assigns.schedule_enabled
    {:noreply, assign(socket, :schedule_enabled, new_enabled)}
  end

  @impl true
  def handle_event("change_schedule_type", %{"mission" => %{"schedule_type" => type}}, socket) do
    schedule_type = if type == "", do: nil, else: String.to_existing_atom(type)
    {:noreply, assign(socket, :schedule_type, schedule_type)}
  end

  @impl true
  def handle_event("toggle_schedule_day", %{"day" => day}, socket) do
    current_days = socket.assigns.schedule_days || []

    new_days =
      if day in current_days do
        Enum.reject(current_days, &(&1 == day))
      else
        [day | current_days]
      end

    {:noreply, assign(socket, :schedule_days, new_days)}
  end

  @impl true
  def handle_event("validate", %{"mission" => mission_params}, socket) do
    # Merge scheduling state into params
    mission_params = merge_schedule_params(mission_params, socket.assigns)
    form = AshPhoenix.Form.validate(socket.assigns.form.source, mission_params)
    {:noreply, assign(socket, :form, to_form(form))}
  end

  @impl true
  def handle_event("save", %{"mission" => mission_params}, socket) do
    # Merge scheduling state into params
    mission_params = merge_schedule_params(mission_params, socket.assigns)

    case AshPhoenix.Form.submit(socket.assigns.form.source, params: mission_params) do
      {:ok, mission} ->
        notify_parent({:saved, mission})

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Mission #{(socket.assigns.action == :new && "created") || "updated"}"
         )
         |> push_patch(to: ~p"/")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp merge_schedule_params(params, assigns) do
    params
    |> Map.put("schedule_enabled", to_string(assigns.schedule_enabled))
    |> Map.put("schedule_type", to_string(assigns.schedule_type || ""))
    |> Map.put("schedule_days", assigns.schedule_days || [])
    |> convert_12h_to_24h()
    |> maybe_convert_datetime_local(assigns.schedule_type)
  end

  defp convert_12h_to_24h(params) do
    if Settings.time_format() == :"12h" do
      case {Map.get(params, "schedule_hour"), Map.get(params, "schedule_ampm")} do
        {nil, _} ->
          params

        {hour_str, ampm} when ampm in ["AM", "PM"] ->
          hour_12 = parse_int(hour_str)

          hour_24 =
            cond do
              ampm == "AM" && hour_12 == 12 -> 0
              ampm == "PM" && hour_12 == 12 -> 12
              ampm == "PM" -> hour_12 + 12
              true -> hour_12
            end

          Map.put(params, "schedule_hour", to_string(hour_24))

        _ ->
          params
      end
    else
      params
    end
  end

  defp maybe_convert_datetime_local(params, :once) do
    case Map.get(params, "next_run_at") do
      nil ->
        params

      "" ->
        params

      datetime_local ->
        case TimezoneHelper.parse_datetime_input(datetime_local) do
          %DateTime{} = utc_datetime ->
            Map.put(params, "next_run_at", DateTime.to_iso8601(utc_datetime))

          _ ->
            params
        end
    end
  end

  defp maybe_convert_datetime_local(params, schedule_type)
       when schedule_type in [:daily, :weekly] do
    # Convert hour from local to UTC if in local mode
    case Settings.timezone_mode() do
      :local ->
        convert_hour_to_utc(params)

      :utc ->
        params
    end
  end

  defp maybe_convert_datetime_local(params, _), do: params

  defp convert_hour_to_utc(params) do
    hour = parse_int(Map.get(params, "schedule_hour"))
    minute = parse_int(Map.get(params, "schedule_minute", "0"))

    case Settings.user_timezone() do
      nil ->
        params

      timezone ->
        # Create a reference datetime in the user's timezone and convert to UTC
        # Use today's date as reference
        today = Date.utc_today()

        case NaiveDateTime.new(today.year, today.month, today.day, hour, minute, 0) do
          {:ok, naive} ->
            case DateTime.from_naive(naive, timezone) do
              {:ok, local_dt} ->
                case DateTime.shift_zone(local_dt, "Etc/UTC") do
                  {:ok, utc_dt} ->
                    params
                    |> Map.put("schedule_hour", to_string(utc_dt.hour))
                    |> Map.put("schedule_minute", to_string(utc_dt.minute))

                  _ ->
                    params
                end

              {:ambiguous, first, _} ->
                case DateTime.shift_zone(first, "Etc/UTC") do
                  {:ok, utc_dt} ->
                    params
                    |> Map.put("schedule_hour", to_string(utc_dt.hour))
                    |> Map.put("schedule_minute", to_string(utc_dt.minute))

                  _ ->
                    params
                end

              {:gap, just_before, _just_after} ->
                case DateTime.shift_zone(just_before, "Etc/UTC") do
                  {:ok, utc_dt} ->
                    params
                    |> Map.put("schedule_hour", to_string(utc_dt.hour))
                    |> Map.put("schedule_minute", to_string(utc_dt.minute))

                  _ ->
                    params
                end

              {:error, _} ->
                params
            end

          _ ->
            params
        end
    end
  end

  defp parse_int(nil), do: 0
  defp parse_int(""), do: 0

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_int(n) when is_integer(n), do: n

  defp format_datetime_for_input(nil), do: ""

  defp format_datetime_for_input(%DateTime{} = dt) do
    TimezoneHelper.format_datetime_input(dt)
  end

  defp format_datetime_for_input(_), do: ""

  defp timezone_label, do: TimezoneHelper.timezone_label()

  defp is_12h_format?, do: Settings.time_format() == :"12h"

  defp format_hour_for_display(nil, default), do: format_hour_for_display(default, default)
  defp format_hour_for_display("", default), do: format_hour_for_display(default, default)

  defp format_hour_for_display(value, _default) do
    hour = parse_int(value)

    if is_12h_format?() do
      hour_12 = rem(hour, 12)
      hour_12 = if hour_12 == 0, do: 12, else: hour_12
      String.pad_leading(to_string(hour_12), 2, "0")
    else
      String.pad_leading(to_string(hour), 2, "0")
    end
  end

  defp get_ampm(nil, default), do: get_ampm(default, default)
  defp get_ampm("", default), do: get_ampm(default, default)

  defp get_ampm(value, _default) do
    hour = parse_int(value)
    if hour >= 12, do: "PM", else: "AM"
  end

  defp pad_number(nil, default), do: String.pad_leading(to_string(default), 2, "0")
  defp pad_number("", default), do: String.pad_leading(to_string(default), 2, "0")

  defp pad_number(value, _default) when is_integer(value) do
    String.pad_leading(to_string(value), 2, "0")
  end

  defp pad_number(value, _default) when is_binary(value) do
    String.pad_leading(value, 2, "0")
  end
end
