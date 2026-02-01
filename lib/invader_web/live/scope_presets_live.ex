defmodule InvaderWeb.ScopePresetsLive do
  @moduledoc """
  LiveView for managing scope presets.
  """
  use InvaderWeb, :live_view

  alias Invader.Scopes.ScopePreset
  alias Invader.Scopes.Parsers.GitHub

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Scope Presets")
      |> assign(:editing, nil)
      |> assign(:show_new_form, false)
      |> assign(:new_preset_name, "")
      |> assign(:new_preset_description, "")
      |> assign(:new_preset_scopes, [])
      |> assign(:show_scope_picker, false)
      |> load_presets()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-black text-white p-8">
      <div class="max-w-4xl mx-auto">
        <!-- Header -->
        <div class="flex items-center justify-between mb-8">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/"} class="text-cyan-500 hover:text-cyan-400">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 19l-7-7 7-7"
                />
              </svg>
            </.link>
            <h1 class="text-2xl text-cyan-400 font-mono">SCOPE PRESETS</h1>
          </div>
          <button
            :if={!@show_new_form}
            phx-click="show_new_form"
            class="arcade-btn border-green-500 text-green-400 text-xs px-4 py-2"
          >
            + NEW PRESET
          </button>
        </div>
        
    <!-- New Preset Form -->
        <div :if={@show_new_form} class="mb-8 p-4 border-2 border-cyan-700 bg-gray-900/50">
          <h2 class="text-cyan-500 text-sm mb-4">CREATE NEW PRESET</h2>
          <form phx-submit="create_preset" class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="text-cyan-500 text-[10px] block mb-1">NAME</label>
                <input
                  type="text"
                  name="name"
                  value={@new_preset_name}
                  phx-change="update_new_name"
                  placeholder="my-preset"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-2 text-sm focus:border-cyan-400 focus:outline-none"
                  required
                />
              </div>
              <div>
                <label class="text-cyan-500 text-[10px] block mb-1">DESCRIPTION</label>
                <input
                  type="text"
                  name="description"
                  value={@new_preset_description}
                  phx-change="update_new_description"
                  placeholder="What this preset allows..."
                  class="w-full bg-black border-2 border-cyan-700 text-white p-2 text-sm focus:border-cyan-400 focus:outline-none"
                />
              </div>
            </div>

            <div>
              <label class="text-cyan-500 text-[10px] block mb-2">SCOPES</label>
              <div class="flex flex-wrap gap-2 mb-2">
                <%= for scope <- @new_preset_scopes do %>
                  <span class="inline-flex items-center gap-1 px-2 py-1 text-xs bg-cyan-900/50 border border-cyan-700 text-cyan-400">
                    {scope}
                    <button
                      type="button"
                      phx-click="remove_new_scope"
                      phx-value-scope={scope}
                      class="text-cyan-600 hover:text-red-400"
                    >
                      x
                    </button>
                  </span>
                <% end %>
              </div>
              
    <!-- Scope picker -->
              <div class="flex flex-wrap gap-2">
                <%= for category <- ["pr", "issue", "repo"] do %>
                  <div class="relative">
                    <button
                      type="button"
                      phx-click="toggle_category_picker"
                      phx-value-category={category}
                      class={"arcade-btn text-[10px] py-1 px-2 #{if category_has_scopes?(category, @new_preset_scopes), do: "border-cyan-400 text-cyan-400", else: "border-cyan-800 text-cyan-600"}"}
                    >
                      {String.upcase(category)}
                    </button>
                  </div>
                <% end %>
                <button
                  type="button"
                  phx-click="add_full_access"
                  class="arcade-btn text-[10px] py-1 px-2 border-green-800 text-green-600 hover:border-green-400"
                >
                  FULL ACCESS
                </button>
              </div>
            </div>

            <div class="flex gap-2 pt-2">
              <button
                type="submit"
                class="arcade-btn border-green-500 text-green-400 text-xs px-4 py-2"
              >
                CREATE
              </button>
              <button
                type="button"
                phx-click="cancel_new"
                class="arcade-btn border-cyan-700 text-cyan-600 text-xs px-4 py-2"
              >
                CANCEL
              </button>
            </div>
          </form>
        </div>
        
    <!-- Presets List -->
        <div class="space-y-4">
          <%= for preset <- @presets do %>
            <div class={"p-4 border-2 #{if preset.is_system, do: "border-purple-700 bg-purple-900/10", else: "border-cyan-700 bg-gray-900/50"}"}>
              <div class="flex items-start justify-between">
                <div class="flex-1">
                  <div class="flex items-center gap-2">
                    <h3 class="text-white font-mono">{preset.name}</h3>
                    <span
                      :if={preset.is_system}
                      class="text-[8px] px-1 py-0.5 bg-purple-900 text-purple-400 border border-purple-700"
                    >
                      SYSTEM
                    </span>
                  </div>
                  <p :if={preset.description} class="text-cyan-600 text-xs mt-1">
                    {preset.description}
                  </p>
                  <div class="flex flex-wrap gap-1 mt-2">
                    <%= for scope <- preset.scopes || [] do %>
                      <span class="text-[10px] px-1.5 py-0.5 bg-cyan-900/30 border border-cyan-800 text-cyan-500">
                        {scope}
                      </span>
                    <% end %>
                  </div>
                  <p class="text-cyan-800 text-[10px] mt-2">
                    Used by {preset.usage_count || 0} mission(s)
                  </p>
                </div>

                <div :if={!preset.is_system} class="flex gap-2">
                  <button
                    phx-click="edit_preset"
                    phx-value-id={preset.id}
                    class="arcade-btn text-[10px] py-1 px-2 border-cyan-700 text-cyan-600 hover:border-cyan-400"
                  >
                    EDIT
                  </button>
                  <button
                    phx-click="delete_preset"
                    phx-value-id={preset.id}
                    data-confirm="Are you sure you want to delete this preset?"
                    class="arcade-btn text-[10px] py-1 px-2 border-red-800 text-red-600 hover:border-red-400"
                  >
                    DELETE
                  </button>
                </div>
              </div>
              
    <!-- Edit form (inline) -->
              <div :if={@editing == preset.id} class="mt-4 pt-4 border-t border-cyan-800">
                <form phx-submit="save_preset" class="space-y-3">
                  <input type="hidden" name="preset_id" value={preset.id} />
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <label class="text-cyan-500 text-[10px] block mb-1">NAME</label>
                      <input
                        type="text"
                        name="name"
                        value={preset.name}
                        class="w-full bg-black border-2 border-cyan-700 text-white p-2 text-sm focus:border-cyan-400 focus:outline-none"
                        required
                      />
                    </div>
                    <div>
                      <label class="text-cyan-500 text-[10px] block mb-1">DESCRIPTION</label>
                      <input
                        type="text"
                        name="description"
                        value={preset.description}
                        class="w-full bg-black border-2 border-cyan-700 text-white p-2 text-sm focus:border-cyan-400 focus:outline-none"
                      />
                    </div>
                  </div>
                  <div class="flex gap-2">
                    <button
                      type="submit"
                      class="arcade-btn border-green-500 text-green-400 text-[10px] px-3 py-1"
                    >
                      SAVE
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_edit"
                      class="arcade-btn border-cyan-700 text-cyan-600 text-[10px] px-3 py-1"
                    >
                      CANCEL
                    </button>
                  </div>
                </form>
              </div>
            </div>
          <% end %>
        </div>

        <div :if={@presets == []} class="text-center text-cyan-700 py-8">
          No scope presets found. Create one to get started.
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("show_new_form", _params, socket) do
    {:noreply, assign(socket, :show_new_form, true)}
  end

  @impl true
  def handle_event("cancel_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_new_form, false)
     |> assign(:new_preset_name, "")
     |> assign(:new_preset_description, "")
     |> assign(:new_preset_scopes, [])}
  end

  @impl true
  def handle_event("update_new_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :new_preset_name, name)}
  end

  @impl true
  def handle_event("update_new_description", %{"description" => desc}, socket) do
    {:noreply, assign(socket, :new_preset_description, desc)}
  end

  @impl true
  def handle_event("toggle_category_picker", %{"category" => category}, socket) do
    all_category_scopes = get_category_scopes(category)
    current_scopes = socket.assigns.new_preset_scopes

    new_scopes =
      if category_has_scopes?(category, current_scopes) do
        Enum.reject(current_scopes, &String.starts_with?(&1, "github:#{category}:"))
      else
        (current_scopes ++ all_category_scopes) |> Enum.uniq() |> Enum.reject(&(&1 == "*"))
      end

    {:noreply, assign(socket, :new_preset_scopes, new_scopes)}
  end

  @impl true
  def handle_event("remove_new_scope", %{"scope" => scope}, socket) do
    new_scopes = Enum.reject(socket.assigns.new_preset_scopes, &(&1 == scope))
    {:noreply, assign(socket, :new_preset_scopes, new_scopes)}
  end

  @impl true
  def handle_event("add_full_access", _params, socket) do
    {:noreply, assign(socket, :new_preset_scopes, ["*"])}
  end

  @impl true
  def handle_event("create_preset", %{"name" => name, "description" => description}, socket) do
    case ScopePreset.create(%{
           name: name,
           description: description,
           scopes: socket.assigns.new_preset_scopes,
           is_system: false
         }) do
      {:ok, _preset} ->
        {:noreply,
         socket
         |> put_flash(:info, "Preset created successfully")
         |> assign(:show_new_form, false)
         |> assign(:new_preset_name, "")
         |> assign(:new_preset_description, "")
         |> assign(:new_preset_scopes, [])
         |> load_presets()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to create preset: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("edit_preset", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, id)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  @impl true
  def handle_event(
        "save_preset",
        %{"preset_id" => id, "name" => name, "description" => description},
        socket
      ) do
    case ScopePreset.get(id) do
      {:ok, preset} ->
        case ScopePreset.update(preset, %{name: name, description: description}) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> put_flash(:info, "Preset updated")
             |> assign(:editing, nil)
             |> load_presets()}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Failed to update: #{inspect(error)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Preset not found")}
    end
  end

  @impl true
  def handle_event("delete_preset", %{"id" => id}, socket) do
    case ScopePreset.get(id) do
      {:ok, preset} ->
        case ScopePreset.destroy(preset) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Preset deleted")
             |> load_presets()}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Failed to delete: #{inspect(error)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Preset not found")}
    end
  end

  defp load_presets(socket) do
    presets = ScopePreset.list!()

    # Calculate usage count for each preset
    presets_with_usage =
      Enum.map(presets, fn preset ->
        # Count missions using this preset
        usage_count = count_preset_usage(preset.id)
        Map.put(preset, :usage_count, usage_count)
      end)

    # Sort: system presets first, then by name
    sorted =
      presets_with_usage
      |> Enum.sort_by(fn p -> {!p.is_system, p.name} end)

    assign(socket, :presets, sorted)
  end

  defp count_preset_usage(preset_id) do
    Invader.Missions.Mission.list!()
    |> Enum.count(&(&1.scope_preset_id == preset_id))
  end

  defp category_has_scopes?(category, scopes) do
    Enum.any?(scopes, &String.starts_with?(&1, "github:#{category}:"))
  end

  defp get_category_scopes(category) do
    GitHub.all_scopes()
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, "github:#{category}:"))
  end
end
