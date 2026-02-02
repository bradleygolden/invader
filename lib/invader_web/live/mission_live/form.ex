defmodule InvaderWeb.MissionLive.Form do
  @moduledoc """
  LiveView for creating and editing missions.
  """
  use InvaderWeb, :live_view

  alias Invader.Agents.AgentConfig
  alias Invader.Missions.Mission
  alias Invader.Missions.GithubRepo
  alias Invader.Sprites.Sprite
  alias Invader.Loadouts.Loadout
  alias Invader.Scopes.ScopePreset
  alias Invader.Connections.Connection
  alias Invader.Connections.GitHub.Executor, as: GitHubExecutor
  alias Invader.Credentials.SavedCredential
  alias Invader.Settings
  alias InvaderWeb.TimezoneHelper

  import InvaderWeb.PageLayout

  @impl true
  def mount(params, _session, socket) do
    action = if params["id"], do: :edit, else: :new

    socket =
      socket
      |> assign(:action, action)
      |> load_mission(params)
      |> load_form_data()

    {:ok, socket}
  end

  defp load_mission(socket, %{"id" => id}) do
    case Invader.Missions.Mission.get(id) do
      {:ok, mission} ->
        mission = Ash.load!(mission, :sprite)

        socket
        |> assign(:page_title, "Edit Mission")
        |> assign(:mission, mission)

      _ ->
        socket
        |> put_flash(:error, "Mission not found")
        |> push_navigate(to: ~p"/")
    end
  end

  defp load_mission(socket, _params) do
    socket
    |> assign(:page_title, "New Mission")
    |> assign(:mission, %Mission{})
  end

  defp load_form_data(socket) do
    action = socket.assigns.action
    mission = socket.assigns.mission

    sprites = Sprite.list!()
    sprite_options = Enum.map(sprites, fn s -> {s.name, s.id} end)

    loadouts = Loadout.list!()
    loadout_options = Enum.map(loadouts, fn l -> {l.name, l.id} end)

    form =
      if action == :new do
        AshPhoenix.Form.for_create(Mission, :create, as: "mission")
      else
        AshPhoenix.Form.for_update(mission, :update, as: "mission")
      end

    prompt_mode =
      cond do
        action == :new -> :inline
        mission.prompt && mission.prompt != "" -> :inline
        true -> :path
      end

    {schedule_enabled, schedule_type, schedule_days} =
      if action == :new do
        {false, nil, []}
      else
        {mission.schedule_enabled || false, mission.schedule_type, mission.schedule_days || []}
      end

    scope_presets = ScopePreset.list!()

    {scope_preset_id, selected_scopes} =
      if action == :new do
        {nil, []}
      else
        {mission.scope_preset_id, mission.scopes || []}
      end

    # Show waves setting only when editing (if max_waves > 1) or when user adds it
    show_waves_setting = action == :edit and (mission.max_waves || 1) > 1

    # Load GitHub repos from connection
    {available_repos, github_connected, github_installation_id} = load_github_repos()

    # Load existing repos for this mission when editing
    selected_repos =
      if action == :edit do
        mission
        |> Ash.load!(:github_repos)
        |> Map.get(:github_repos, [])
        |> Enum.map(&%{owner: &1.owner, name: &1.name, full_name: "#{&1.owner}/#{&1.name}"})
      else
        []
      end

    # Sprite creation mode (only for new missions)
    create_new_sprite = action == :new && Enum.empty?(sprite_options)
    sprite_name = if action == :new, do: generate_sprite_name(), else: nil
    sprite_lifecycle = :keep
    agent_type = :claude_code
    agent_provider = :anthropic_subscription
    agent_api_key = ""

    # Load saved credentials for auto-fill
    saved_credentials = load_saved_credentials()

    socket
    |> assign(:sprite_options, sprite_options)
    |> assign(:loadout_options, loadout_options)
    |> assign(:prompt_mode, prompt_mode)
    |> assign(:schedule_enabled, schedule_enabled)
    |> assign(:schedule_type, schedule_type)
    |> assign(:schedule_days, schedule_days)
    |> assign(:save_as_loadout, false)
    |> assign(:loadout_name, "")
    |> assign(:scope_presets, scope_presets)
    |> assign(:scope_preset_id, scope_preset_id)
    |> assign(:selected_scopes, selected_scopes)
    |> assign(:show_scope_editor, false)
    |> assign(:show_waves_setting, show_waves_setting)
    |> assign(:available_repos, available_repos)
    |> assign(:selected_repos, selected_repos)
    |> assign(:github_connected, github_connected)
    |> assign(:github_installation_id, github_installation_id)
    |> assign(:show_repo_selector, false)
    # Sprite creation assigns
    |> assign(:create_new_sprite, create_new_sprite)
    |> assign(:sprite_name, sprite_name)
    |> assign(:sprite_lifecycle, sprite_lifecycle)
    |> assign(:agent_type, agent_type)
    |> assign(:agent_provider, agent_provider)
    |> assign(:agent_api_key, agent_api_key)
    |> assign(:agent_options, AgentConfig.agent_options())
    |> assign(:provider_options, AgentConfig.providers_for_agent(agent_type))
    |> assign(:lifecycle_options, AgentConfig.lifecycle_options())
    |> assign(:saved_credentials, saved_credentials)
    |> assign(:save_api_key, false)
    |> assign(:form, to_form(form))
  end

  defp generate_sprite_name do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "mission-#{suffix}"
  end

  defp load_github_repos do
    case Connection.get_by_type(:github) do
      {:ok, connection} ->
        repos =
          case GitHubExecutor.list_repos(connection, limit: 100) do
            {:ok, repos} -> repos
            {:error, _} -> []
          end

        {repos, true, connection.installation_id}

      {:error, _} ->
        {[], false, nil}
    end
  end

  defp load_saved_credentials do
    SavedCredential.list!()
    |> Enum.map(fn cred -> {cred.provider, cred} end)
    |> Map.new()
  end

  defp maybe_save_api_key(%{save_api_key: true, agent_provider: provider, agent_api_key: api_key})
       when api_key != "" and provider in [:anthropic_api, :zai] do
    provider_config = AgentConfig.get_provider(provider)
    name = provider_config[:name] || to_string(provider)

    # Try to create or update existing credential
    case SavedCredential.get_by_provider(provider) do
      {:ok, existing} ->
        SavedCredential.update(existing, %{api_key: api_key})

      {:error, _} ->
        SavedCredential.create(%{
          provider: provider,
          name: name,
          api_key: api_key
        })
    end
  end

  defp maybe_save_api_key(_assigns), do: :ok

  defp save_github_repos(mission, selected_repos) do
    # First, delete existing repos for this mission
    mission
    |> Ash.load!(:github_repos)
    |> Map.get(:github_repos, [])
    |> Enum.each(fn repo ->
      GithubRepo.destroy!(repo)
    end)

    # Then create new ones
    Enum.each(selected_repos, fn repo ->
      GithubRepo.create!(%{
        mission_id: mission.id,
        owner: repo.owner,
        name: repo.name
      })
    end)
  end

  @impl true
  def handle_event("set_prompt_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :prompt_mode, String.to_existing_atom(mode))}
  end

  @impl true
  def handle_event("select_loadout", params, socket) do
    loadout_id = Map.get(params, "loadout_id", "")

    if loadout_id != "" do
      case Loadout.get(loadout_id) do
        {:ok, loadout} ->
          {prompt_mode, form_updates} =
            cond do
              loadout.content && loadout.content != "" ->
                {:inline, %{"prompt" => loadout.content, "prompt_path" => ""}}

              loadout.file_path && loadout.file_path != "" ->
                {:path, %{"prompt_path" => loadout.file_path, "prompt" => ""}}

              true ->
                {socket.assigns.prompt_mode, %{}}
            end

          form = AshPhoenix.Form.validate(socket.assigns.form.source, form_updates)

          {:noreply,
           socket
           |> assign(:prompt_mode, prompt_mode)
           |> assign(:form, to_form(form))}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_save_as_loadout", _params, socket) do
    {:noreply, assign(socket, :save_as_loadout, !socket.assigns.save_as_loadout)}
  end

  @impl true
  def handle_event("update_loadout_name", %{"loadout_name" => name}, socket) do
    {:noreply, assign(socket, :loadout_name, name)}
  end

  @impl true
  def handle_event("toggle_schedule", _params, socket) do
    {:noreply, assign(socket, :schedule_enabled, !socket.assigns.schedule_enabled)}
  end

  @impl true
  def handle_event("toggle_waves_setting", _params, socket) do
    {:noreply, assign(socket, :show_waves_setting, !socket.assigns.show_waves_setting)}
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
    mission_params = merge_schedule_params(mission_params, socket.assigns)
    form = AshPhoenix.Form.validate(socket.assigns.form.source, mission_params)
    {:noreply, assign(socket, :form, to_form(form))}
  end

  @impl true
  def handle_event("save", %{"mission" => mission_params} = params, socket) do
    mission_params = merge_schedule_params(mission_params, socket.assigns)

    # Add agent configuration for all new missions
    mission_params =
      if socket.assigns.action == :new do
        mission_params
        |> Map.put("agent_type", to_string(socket.assigns.agent_type))
        |> Map.put("agent_provider", to_string(socket.assigns.agent_provider))
        |> then(fn p ->
          if socket.assigns.agent_api_key != "" do
            Map.put(p, "agent_api_key", socket.assigns.agent_api_key)
          else
            p
          end
        end)
      else
        mission_params
      end

    # Add sprite creation params if creating new sprite
    mission_params =
      if socket.assigns.action == :new && socket.assigns.create_new_sprite do
        mission_params
        |> Map.put("sprite_name", socket.assigns.sprite_name)
        |> Map.put("sprite_lifecycle", to_string(socket.assigns.sprite_lifecycle))
      else
        mission_params
      end

    loadout_result =
      if socket.assigns.save_as_loadout do
        loadout_name = Map.get(params, "loadout_name", socket.assigns.loadout_name)

        if loadout_name && loadout_name != "" do
          loadout_params =
            if socket.assigns.prompt_mode == :inline do
              %{name: loadout_name, content: Map.get(mission_params, "prompt")}
            else
              %{name: loadout_name, file_path: Map.get(mission_params, "prompt_path")}
            end

          Loadout.create(loadout_params)
        else
          {:ok, :skipped}
        end
      else
        {:ok, :skipped}
      end

    # Use different action based on sprite creation mode
    form =
      if socket.assigns.action == :new && socket.assigns.create_new_sprite do
        AshPhoenix.Form.for_create(Mission, :create_with_sprite, as: "mission")
      else
        socket.assigns.form.source
      end

    case AshPhoenix.Form.submit(form, params: mission_params) do
      {:ok, mission} ->
        # Save GitHub repos for this mission
        save_github_repos(mission, socket.assigns.selected_repos)

        # Save API key for later if requested
        maybe_save_api_key(socket.assigns)

        flash_message =
          cond do
            socket.assigns.create_new_sprite ->
              "Mission created - sprite provisioning started"

            loadout_result == {:ok, %Loadout{}} ->
              "Mission #{if socket.assigns.action == :new, do: "created", else: "updated"} and loadout saved"

            true ->
              "Mission #{if socket.assigns.action == :new, do: "created", else: "updated"}"
          end

        {:noreply,
         socket
         |> put_flash(:info, flash_message)
         |> push_navigate(to: ~p"/")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def handle_event("select_scope_preset", %{"scope_preset_id" => preset_id}, socket) do
    preset_id = if preset_id == "", do: nil, else: preset_id

    {:noreply,
     socket
     |> assign(:scope_preset_id, preset_id)
     |> assign(:show_scope_editor, false)}
  end

  @impl true
  def handle_event("toggle_scope_editor", _params, socket) do
    {:noreply, assign(socket, :show_scope_editor, !socket.assigns.show_scope_editor)}
  end

  @impl true
  def handle_event("toggle_scope_category", %{"category" => category}, socket) do
    all_category_scopes = get_category_scopes(category)
    current_scopes = socket.assigns.selected_scopes

    new_scopes =
      if category_has_scopes?(category, current_scopes) do
        Enum.reject(current_scopes, &String.starts_with?(&1, "github:#{category}:"))
      else
        (current_scopes ++ all_category_scopes) |> Enum.uniq()
      end

    {:noreply, assign(socket, :selected_scopes, new_scopes)}
  end

  @impl true
  def handle_event("remove_scope", %{"scope" => scope}, socket) do
    new_scopes = Enum.reject(socket.assigns.selected_scopes, &(&1 == scope))
    {:noreply, assign(socket, :selected_scopes, new_scopes)}
  end

  @impl true
  def handle_event("set_full_access", _params, socket) do
    {:noreply, assign(socket, :selected_scopes, ["*"])}
  end

  @impl true
  def handle_event("clear_scopes", _params, socket) do
    {:noreply, assign(socket, :selected_scopes, [])}
  end

  # GitHub repo event handlers

  @impl true
  def handle_event("toggle_repo_selector", _params, socket) do
    {:noreply, assign(socket, :show_repo_selector, !socket.assigns.show_repo_selector)}
  end

  @impl true
  def handle_event("toggle_repo", %{"repo" => full_name}, socket) do
    selected = socket.assigns.selected_repos
    available = socket.assigns.available_repos

    new_selected =
      if Enum.any?(selected, &(&1.full_name == full_name)) do
        Enum.reject(selected, &(&1.full_name == full_name))
      else
        case Enum.find(available, &(&1.full_name == full_name)) do
          nil -> selected
          repo -> [repo | selected]
        end
      end

    {:noreply, assign(socket, :selected_repos, new_selected)}
  end

  @impl true
  def handle_event("remove_repo", %{"repo" => full_name}, socket) do
    new_selected = Enum.reject(socket.assigns.selected_repos, &(&1.full_name == full_name))
    {:noreply, assign(socket, :selected_repos, new_selected)}
  end

  @impl true
  def handle_event("clear_repos", _params, socket) do
    {:noreply, assign(socket, :selected_repos, [])}
  end

  # Sprite creation event handlers

  @impl true
  def handle_event("toggle_create_sprite", _params, socket) do
    {:noreply, assign(socket, :create_new_sprite, !socket.assigns.create_new_sprite)}
  end

  @impl true
  def handle_event("update_sprite_name", %{"sprite_name" => name}, socket) do
    {:noreply, assign(socket, :sprite_name, name)}
  end

  @impl true
  def handle_event("change_agent_type", %{"agent_type" => type}, socket) do
    agent_type = String.to_existing_atom(type)
    provider_options = AgentConfig.providers_for_agent(agent_type)
    # Default to first available provider for this agent
    default_provider =
      case provider_options do
        [{_, p} | _] -> p
        _ -> :anthropic_subscription
      end

    {:noreply,
     socket
     |> assign(:agent_type, agent_type)
     |> assign(:provider_options, provider_options)
     |> assign(:agent_provider, default_provider)
     |> assign(:agent_api_key, "")}
  end

  @impl true
  def handle_event("change_agent_provider", %{"agent_provider" => provider}, socket) do
    provider_atom = String.to_existing_atom(provider)

    # Check for saved credential for this provider
    {api_key, has_saved} =
      case Map.get(socket.assigns.saved_credentials, provider_atom) do
        %SavedCredential{api_key: key} -> {key, true}
        _ -> {"", false}
      end

    {:noreply,
     socket
     |> assign(:agent_provider, provider_atom)
     |> assign(:agent_api_key, api_key)
     |> assign(:save_api_key, not has_saved)}
  end

  @impl true
  def handle_event("change_sprite_lifecycle", %{"sprite_lifecycle" => lifecycle}, socket) do
    {:noreply, assign(socket, :sprite_lifecycle, String.to_existing_atom(lifecycle))}
  end

  @impl true
  def handle_event("update_agent_api_key", %{"agent_api_key" => key}, socket) do
    {:noreply, assign(socket, :agent_api_key, key)}
  end

  @impl true
  def handle_event("toggle_save_api_key", %{"save_api_key" => value}, socket) do
    {:noreply, assign(socket, :save_api_key, value == "true")}
  end

  defp merge_schedule_params(params, assigns) do
    params
    |> Map.put("schedule_enabled", to_string(assigns.schedule_enabled))
    |> Map.put("schedule_type", to_string(assigns.schedule_type || ""))
    |> Map.put("schedule_days", assigns.schedule_days || [])
    |> merge_scope_params(assigns)
    |> convert_12h_to_24h()
    |> maybe_convert_datetime_local(assigns.schedule_type)
  end

  defp merge_scope_params(params, assigns) do
    params
    |> Map.put("scope_preset_id", assigns.scope_preset_id)
    |> Map.put("scopes", assigns.selected_scopes)
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
    case Settings.timezone_mode() do
      :local -> convert_hour_to_utc(params)
      :utc -> params
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

              {:gap, just_before, _} ->
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

  defp category_has_scopes?(category, selected_scopes) do
    Enum.any?(selected_scopes, &String.starts_with?(&1, "github:#{category}:"))
  end

  defp get_effective_scopes_for_preview(nil, selected_scopes, _presets), do: selected_scopes
  defp get_effective_scopes_for_preview("", selected_scopes, _presets), do: selected_scopes

  defp get_effective_scopes_for_preview(preset_id, _selected_scopes, presets) do
    case Enum.find(presets, &(to_string(&1.id) == to_string(preset_id))) do
      nil -> []
      preset -> preset.scopes
    end
  end

  defp get_category_scopes(category) do
    Invader.Scopes.Parsers.GitHub.all_scopes()
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, "github:#{category}:"))
  end

  defp timezone_label, do: TimezoneHelper.timezone_label()
  defp is_12h_format?, do: Settings.time_format() == :"12h"

  defp provider_requires_api_key?(provider) do
    case AgentConfig.get_provider(provider) do
      %{requires_api_key: true} -> true
      _ -> false
    end
  end

  defp provider_key_placeholder(provider) do
    case AgentConfig.get_provider(provider) do
      %{key_placeholder: placeholder} -> placeholder
      _ -> "API key"
    end
  end

  defp has_saved_credential?(saved_credentials, provider) do
    Map.has_key?(saved_credentials, provider)
  end

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

  defp pad_number(value, _default) when is_integer(value),
    do: String.pad_leading(to_string(value), 2, "0")

  defp pad_number(value, _default) when is_binary(value), do: String.pad_leading(value, 2, "0")

  defp format_datetime_for_input(nil), do: ""
  defp format_datetime_for_input(%DateTime{} = dt), do: TimezoneHelper.format_datetime_input(dt)
  defp format_datetime_for_input(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <.arcade_page page_title={if @action == :new, do: "NEW MISSION", else: "EDIT MISSION"}>
      <div class="text-xs">
        <.form
          for={@form}
          id="mission-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
          autocomplete="off"
          data-1p-ignore
          data-lpignore="true"
        >
          <!-- Sprite Selection / Creation -->
          <div :if={@action == :new} class="space-y-4">
            <!-- Toggle between existing and new sprite -->
            <div class="flex gap-3">
              <button
                type="button"
                phx-click="toggle_create_sprite"
                class={"arcade-btn text-[8px] py-2 px-3 #{if not @create_new_sprite, do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}
              >
                USE EXISTING
              </button>
              <button
                type="button"
                phx-click="toggle_create_sprite"
                class={"arcade-btn text-[8px] py-2 px-3 #{if @create_new_sprite, do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}
              >
                CREATE NEW
              </button>
            </div>
            
    <!-- Existing Sprite Selection -->
            <div :if={not @create_new_sprite} class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">SELECT SPRITE</label>
              <select
                name={@form[:sprite_id].name}
                id={@form[:sprite_id].id}
                class={[
                  "w-full bg-black border-2 text-white p-3 focus:outline-none",
                  @form[:sprite_id].errors == [] && "border-cyan-700 focus:border-cyan-400",
                  @form[:sprite_id].errors != [] && "border-red-500 focus:border-red-400"
                ]}
              >
                <option value="">-- SELECT --</option>
                <%= for {name, id} <- @sprite_options do %>
                  <option value={id} selected={to_string(@form[:sprite_id].value) == to_string(id)}>
                    {name}
                  </option>
                <% end %>
              </select>
              <p :if={@form[:sprite_id].errors != []} class="text-red-500 text-[10px] mt-1">
                Sprite is required
              </p>
            </div>
            
    <!-- New Sprite Creation -->
            <div :if={@create_new_sprite} class="space-y-4 p-3 border border-cyan-900 bg-gray-900/50">
              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">SPRITE NAME</label>
                <input
                  type="text"
                  name="sprite_name"
                  value={@sprite_name}
                  phx-change="update_sprite_name"
                  phx-debounce="300"
                  placeholder="mission-abc123"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
                <p class="text-cyan-700 text-[8px]">
                  A new sprite will be created with this name on sprites.dev
                </p>
              </div>

              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">SPRITE LIFECYCLE</label>
                <select
                  name="sprite_lifecycle"
                  phx-change="change_sprite_lifecycle"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                >
                  <%= for {name, value} <- @lifecycle_options do %>
                    <option value={value} selected={@sprite_lifecycle == value}>
                      {name}
                    </option>
                  <% end %>
                </select>
              </div>
            </div>
            
    <!-- Coding Agent Configuration (for both new and existing sprites) -->
            <div class="space-y-4 p-3 border border-cyan-900 bg-gray-900/50">
              <div class="text-cyan-400 text-[10px] font-bold">CODING AGENT</div>

              <div class="grid grid-cols-2 gap-4">
                <div class="space-y-2">
                  <label class="text-cyan-500 text-[10px] block">AGENT</label>
                  <div class="text-white p-3 border-2 border-cyan-800 bg-gray-900/50">
                    Claude Code
                  </div>
                </div>

                <div class="space-y-2">
                  <label class="text-cyan-500 text-[10px] block">API PROVIDER</label>
                  <select
                    name="agent_provider"
                    phx-change="change_agent_provider"
                    class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                  >
                    <%= for {name, value} <- @provider_options do %>
                      <option value={value} selected={@agent_provider == value}>
                        {name}
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>
              
    <!-- API Key Input (shown when provider requires it) -->
              <div :if={provider_requires_api_key?(@agent_provider)} class="space-y-2">
                <div class="flex items-center justify-between">
                  <label class="text-cyan-500 text-[10px] block">
                    API KEY <span class="text-red-500">*</span>
                  </label>
                  <%= if has_saved_credential?(@saved_credentials, @agent_provider) do %>
                    <span class="text-green-500 text-[8px]">SAVED</span>
                  <% end %>
                </div>
                <input
                  type="password"
                  name="agent_api_key"
                  value={@agent_api_key}
                  phx-change="update_agent_api_key"
                  phx-debounce="300"
                  placeholder={provider_key_placeholder(@agent_provider)}
                  required
                  autocomplete="new-password"
                  data-1p-ignore="true"
                  data-lpignore="true"
                  data-form-type="other"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
                <div class="flex items-center justify-between">
                  <p class="text-cyan-700 text-[8px]">
                    Required for this provider. Will be injected into the sprite automatically.
                  </p>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      name="save_api_key"
                      value="true"
                      checked={@save_api_key}
                      phx-change="toggle_save_api_key"
                      class="w-3 h-3 accent-cyan-500"
                    />
                    <span class="text-cyan-600 text-[8px]">Save for later</span>
                  </label>
                </div>
              </div>

              <p
                :if={not provider_requires_api_key?(@agent_provider)}
                class="text-cyan-600 text-[9px]"
              >
                With subscription mode, you'll need to login via the sprite console after creation.
              </p>
            </div>
          </div>

          <div :if={@action == :edit} class="py-2 border-b border-cyan-800">
            <span class="text-cyan-500 text-[10px]">SPRITE</span>
            <div class="text-white mt-1">{@mission.sprite.name}</div>
          </div>
          
    <!-- Loadout Quick Load -->
          <div :if={length(@loadout_options) > 0} class="space-y-2">
            <label class="text-cyan-500 text-[10px] block">QUICK LOAD</label>
            <div class="flex gap-2">
              <select
                id="loadout-select"
                name="loadout_id"
                phx-change="select_loadout"
                class="flex-1 bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
              >
                <option value="">-- SELECT LOADOUT --</option>
                <%= for {name, id} <- @loadout_options do %>
                  <option value={id}>{name}</option>
                <% end %>
              </select>
              <.link
                navigate={~p"/loadouts"}
                class="arcade-btn p-2 border-cyan-800 text-cyan-600 hover:border-cyan-400 hover:text-cyan-400"
                title="Manage loadouts"
              >
                <svg
                  viewBox="0 0 16 16"
                  class="w-4 h-4 fill-current"
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
              </.link>
            </div>
          </div>
          
    <!-- Prompt Type Toggle -->
          <div class="space-y-3">
            <div class="flex gap-3">
              <button
                type="button"
                phx-click="set_prompt_mode"
                phx-value-mode="path"
                class={"arcade-btn text-[8px] py-2 px-3 #{if @prompt_mode == :path, do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}
              >
                FILE PATH
              </button>
              <button
                type="button"
                phx-click="set_prompt_mode"
                phx-value-mode="inline"
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
            
    <!-- Save as Loadout -->
            <div class="pt-2 border-t border-cyan-900">
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={@save_as_loadout}
                  phx-click="toggle_save_as_loadout"
                  class="w-4 h-4 bg-black border-2 border-cyan-700 text-cyan-400 focus:ring-cyan-500"
                />
                <span class="text-cyan-500 text-[10px]">SAVE AS LOADOUT</span>
              </label>
              <div :if={@save_as_loadout} class="mt-2">
                <input
                  type="text"
                  name="loadout_name"
                  value={@loadout_name}
                  phx-change="update_loadout_name"
                  placeholder="Loadout name..."
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
              </div>
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
              <%= if @show_waves_setting do %>
                <div class="flex items-center justify-between">
                  <label class="text-cyan-500 text-[10px]">MAX WAVES</label>
                  <button
                    type="button"
                    phx-click="toggle_waves_setting"
                    class="text-gray-500 hover:text-cyan-400 text-[10px]"
                  >
                    [REMOVE]
                  </button>
                </div>
                <input
                  type="number"
                  name={@form[:max_waves].name}
                  id={@form[:max_waves].id}
                  value={@form[:max_waves].value}
                  min="1"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
              <% else %>
                <input type="hidden" name={@form[:max_waves].name} value="1" />
                <div class="flex items-center h-full pt-4">
                  <button
                    type="button"
                    phx-click="toggle_waves_setting"
                    class="text-cyan-400 hover:text-cyan-300 text-[10px] flex items-center gap-2"
                  >
                    <span>+ ADD WAVES</span>
                    <span
                      class="text-gray-500 cursor-help"
                      title="Waves are iterations - how many times the mission will loop through its prompt. Default is 1 (single run)."
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                    </span>
                  </button>
                </div>
              <% end %>
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
                <label class="text-cyan-500 text-[10px] block">
                  RUN AT TIME ({timezone_label()})
                </label>
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
          
    <!-- Scopes Section -->
          <div class="space-y-4 pt-4 border-t border-cyan-800">
            <div class="flex items-center justify-between">
              <label class="text-cyan-500 text-[10px]">CLI SCOPES</label>
              <InvaderWeb.ScopeComponents.scope_badge count={length(@selected_scopes)} />
            </div>
            
    <!-- Preset Selector -->
            <div class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">PRESET</label>
              <select
                name="scope_preset_id"
                phx-change="select_scope_preset"
                class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
              >
                <option value="">-- Custom Scopes --</option>
                <%= for preset <- @scope_presets do %>
                  <option
                    value={preset.id}
                    selected={to_string(@scope_preset_id) == to_string(preset.id)}
                  >
                    {preset.name}
                    <%= if preset.is_system do %>
                      (System)
                    <% end %>
                  </option>
                <% end %>
              </select>
            </div>
            
    <!-- Custom Scopes Toggle -->
            <div :if={is_nil(@scope_preset_id) or @scope_preset_id == ""} class="space-y-3">
              <div class="flex items-center gap-3">
                <button
                  type="button"
                  phx-click="toggle_scope_editor"
                  class={"arcade-btn text-[8px] py-1 px-2 #{if @show_scope_editor, do: "border-cyan-400 text-cyan-400", else: "border-cyan-800 text-cyan-600"}"}
                >
                  {if @show_scope_editor, do: "HIDE EDITOR", else: "SHOW EDITOR"}
                </button>
                <span class="text-cyan-700 text-[8px]">
                  {length(@selected_scopes)} scopes selected
                </span>
              </div>

              <div
                :if={@show_scope_editor}
                class="space-y-3 p-3 border border-cyan-900 bg-gray-900/50"
              >
                <!-- Category toggles -->
                <div class="flex flex-wrap gap-2">
                  <%= for category <- ["pr", "issue", "repo"] do %>
                    <button
                      type="button"
                      phx-click="toggle_scope_category"
                      phx-value-category={category}
                      class={"arcade-btn text-[8px] py-1 px-2 #{if category_has_scopes?(category, @selected_scopes), do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}
                    >
                      {String.upcase(category)}
                    </button>
                  <% end %>
                </div>
                
    <!-- Selected scopes display -->
                <div :if={@selected_scopes != []} class="flex flex-wrap gap-1">
                  <%= for scope <- @selected_scopes do %>
                    <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[8px] bg-cyan-900/50 border border-cyan-700 text-cyan-400">
                      {scope}
                      <button
                        type="button"
                        phx-click="remove_scope"
                        phx-value-scope={scope}
                        class="text-cyan-600 hover:text-red-400"
                      >
                        x
                      </button>
                    </span>
                  <% end %>
                </div>
                
    <!-- Full access shortcut -->
                <div class="flex gap-2">
                  <button
                    type="button"
                    phx-click="set_full_access"
                    class="arcade-btn text-[8px] py-1 px-2 border-green-800 text-green-600 hover:border-green-400 hover:text-green-400"
                  >
                    FULL ACCESS
                  </button>
                  <button
                    type="button"
                    phx-click="clear_scopes"
                    class="arcade-btn text-[8px] py-1 px-2 border-red-800 text-red-600 hover:border-red-400 hover:text-red-400"
                  >
                    CLEAR ALL
                  </button>
                </div>
              </div>
            </div>
            
    <!-- Preview -->
            <div :if={@selected_scopes != [] or @scope_preset_id} class="space-y-2">
              <InvaderWeb.ScopeComponents.scope_preview scopes={
                get_effective_scopes_for_preview(@scope_preset_id, @selected_scopes, @scope_presets)
              } />
            </div>
          </div>
          
    <!-- GitHub Repos Section -->
          <div class="space-y-4 pt-4 border-t border-cyan-800">
            <div class="flex items-center justify-between">
              <label class="text-cyan-500 text-[10px]">GITHUB REPOS</label>
              <span class="text-[8px] px-2 py-0.5 bg-cyan-900/50 border border-cyan-700 text-cyan-400">
                {length(@selected_repos)}
              </span>
            </div>

            <p class="text-cyan-700 text-[9px]">
              Selected repos will be automatically cloned to the sprite when the mission starts.
            </p>

            <div :if={not @github_connected} class="text-yellow-500 text-[10px]">
              GitHub not connected.
              <.link navigate={~p"/connections"} class="underline hover:text-yellow-400">
                Configure connection
              </.link>
            </div>

            <div :if={@github_connected} class="space-y-3">
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  phx-click="toggle_repo_selector"
                  class={"arcade-btn text-[8px] py-1 px-2 #{if @show_repo_selector, do: "border-cyan-400 text-cyan-400", else: "border-cyan-800 text-cyan-600"}"}
                >
                  {if @show_repo_selector, do: "HIDE REPOS", else: "SELECT REPOS"}
                </button>
                <a
                  :if={@github_installation_id}
                  href={"https://github.com/settings/installations/#{@github_installation_id}"}
                  target="_blank"
                  class="text-[8px] text-cyan-600 hover:text-cyan-400 underline"
                >
                  + Add more repos
                </a>
              </div>

              <div
                :if={@show_repo_selector}
                class="space-y-2 p-3 border border-cyan-900 bg-gray-900/50 max-h-48 overflow-y-auto"
              >
                <div :if={@available_repos == []} class="text-cyan-700 text-[10px]">
                  No repositories found.
                </div>
                <%= for repo <- @available_repos do %>
                  <label class="flex items-center gap-2 cursor-pointer hover:bg-cyan-900/30 p-1">
                    <input
                      type="checkbox"
                      checked={Enum.any?(@selected_repos, &(&1.full_name == repo.full_name))}
                      phx-click="toggle_repo"
                      phx-value-repo={repo.full_name}
                      class="w-4 h-4 bg-black border-2 border-cyan-700 text-cyan-400 focus:ring-cyan-500"
                    />
                    <span class="text-white text-[10px]">{repo.full_name}</span>
                    <span :if={repo.description} class="text-cyan-700 text-[8px] truncate">
                      - {repo.description}
                    </span>
                  </label>
                <% end %>
              </div>

              <div :if={@selected_repos != []} class="space-y-2">
                <div class="flex flex-wrap gap-1">
                  <%= for repo <- @selected_repos do %>
                    <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[8px] bg-cyan-900/50 border border-cyan-700 text-cyan-400">
                      {repo.full_name}
                      <button
                        type="button"
                        phx-click="remove_repo"
                        phx-value-repo={repo.full_name}
                        class="text-cyan-600 hover:text-red-400"
                      >
                        x
                      </button>
                    </span>
                  <% end %>
                </div>
                <button
                  type="button"
                  phx-click="clear_repos"
                  class="arcade-btn text-[8px] py-1 px-2 border-red-800 text-red-600 hover:border-red-400 hover:text-red-400"
                >
                  CLEAR ALL
                </button>
              </div>
            </div>
          </div>
          
    <!-- Actions -->
          <div class="flex justify-end gap-4 pt-6 mt-6 border-t border-cyan-800">
            <button
              type="submit"
              phx-disable-with="SAVING..."
              class="arcade-btn border-green-500 text-green-400 text-[10px]"
            >
              {if @action == :new, do: "CREATE", else: "UPDATE"}
            </button>
          </div>
        </.form>
      </div>
    </.arcade_page>
    """
  end
end
