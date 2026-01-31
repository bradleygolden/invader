defmodule InvaderWeb.LoadoutsComponent do
  @moduledoc """
  LiveComponent for managing loadouts (reusable prompt configurations).
  """
  use InvaderWeb, :live_component

  alias Invader.Loadouts.Loadout

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <div class="space-y-4">
        <!-- Loadouts List -->
        <div class="space-y-2 max-h-64 overflow-y-auto">
          <%= if Enum.empty?(@loadouts) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- NO LOADOUTS SAVED -</p>
          <% else %>
            <%= for loadout <- @loadouts do %>
              <div class="border border-cyan-800 p-3 hover:bg-cyan-900/10 transition-colors">
                <div class="flex justify-between items-start">
                  <div class="flex-1">
                    <div class="text-white text-xs font-medium">{loadout.name}</div>
                    <div class="text-cyan-600 text-[8px] mt-1">
                      <%= if loadout.content do %>
                        <span class="text-cyan-500">[INLINE]</span>
                        <span class="ml-2 truncate max-w-xs inline-block align-bottom">
                          {String.slice(loadout.content, 0, 50)}{if String.length(
                                                                      loadout.content || ""
                                                                    ) > 50, do: "..."}
                        </span>
                      <% else %>
                        <span class="text-cyan-500">[FILE]</span>
                        <span class="ml-2">{Path.basename(loadout.file_path || "")}</span>
                      <% end %>
                    </div>
                    <%= if loadout.description do %>
                      <div class="text-cyan-700 text-[8px] mt-1">{loadout.description}</div>
                    <% end %>
                  </div>
                  <div class="flex gap-2 ml-2">
                    <button
                      phx-click="edit_loadout"
                      phx-value-id={loadout.id}
                      phx-target={@myself}
                      class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
                    >
                      EDIT
                    </button>
                    <button
                      phx-click="delete_loadout"
                      phx-value-id={loadout.id}
                      phx-target={@myself}
                      data-confirm="Delete this loadout?"
                      class="arcade-btn border-red-500 text-red-400 text-[8px] py-1.5 px-1.5 sm:py-1 sm:px-2"
                    >
                      DEL
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
        
    <!-- New/Edit Loadout Form -->
        <div class="pt-4 border-t border-cyan-800">
          <div class="text-cyan-500 text-[10px] mb-3">
            {if @editing_loadout, do: "EDIT LOADOUT", else: "NEW LOADOUT"}
          </div>
          <.form
            for={@form}
            id="loadout-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save_loadout"
            class="space-y-4"
          >
            <div class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">NAME</label>
              <input
                type="text"
                name={@form[:name].name}
                value={@form[:name].value}
                placeholder="My loadout name..."
                class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
              />
            </div>

            <div class="space-y-2">
              <label class="text-cyan-500 text-[10px] block">DESCRIPTION (OPTIONAL)</label>
              <input
                type="text"
                name={@form[:description].name}
                value={@form[:description].value}
                placeholder="What does this loadout do?"
                class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
              />
            </div>

            <div class="space-y-3">
              <div class="flex gap-3">
                <button
                  type="button"
                  phx-click="set_loadout_mode"
                  phx-value-mode="path"
                  phx-target={@myself}
                  class={"arcade-btn text-[8px] py-2 px-3 #{if @loadout_mode == :path, do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}
                >
                  FILE PATH
                </button>
                <button
                  type="button"
                  phx-click="set_loadout_mode"
                  phx-value-mode="inline"
                  phx-target={@myself}
                  class={"arcade-btn text-[8px] py-2 px-3 #{if @loadout_mode == :inline, do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"}"}
                >
                  INLINE
                </button>
              </div>

              <div :if={@loadout_mode == :path} class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">FILE PATH</label>
                <input
                  type="text"
                  name={@form[:file_path].name}
                  value={@form[:file_path].value}
                  placeholder="/path/to/PROMPT.md"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
              </div>

              <div :if={@loadout_mode == :inline} class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">PROMPT CONTENT</label>
                <textarea
                  name={@form[:content].name}
                  placeholder="Enter your prompt..."
                  rows="4"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none resize-none"
                >{@form[:content].value}</textarea>
              </div>
            </div>

            <div class="flex justify-end gap-3 pt-3">
              <%= if @editing_loadout do %>
                <button
                  type="button"
                  phx-click="cancel_edit"
                  phx-target={@myself}
                  class="arcade-btn border-cyan-600 text-cyan-400 text-[10px]"
                >
                  CANCEL
                </button>
              <% end %>
              <button
                type="submit"
                phx-disable-with="SAVING..."
                class="arcade-btn border-green-500 text-green-400 text-[10px]"
              >
                {if @editing_loadout, do: "UPDATE", else: "CREATE"}
              </button>
            </div>
          </.form>
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
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    loadouts = Loadout.list!()

    form =
      if socket.assigns[:editing_loadout] do
        socket.assigns.form
      else
        AshPhoenix.Form.for_create(Loadout, :create, as: "loadout") |> to_form()
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:loadouts, loadouts)
     |> assign_new(:form, fn -> form end)
     |> assign_new(:loadout_mode, fn -> :inline end)
     |> assign_new(:editing_loadout, fn -> nil end)}
  end

  @impl true
  def handle_event("set_loadout_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :loadout_mode, String.to_existing_atom(mode))}
  end

  @impl true
  def handle_event("validate", %{"loadout" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, :form, to_form(form))}
  end

  @impl true
  def handle_event("save_loadout", %{"loadout" => params}, socket) do
    # Clear the field that isn't being used based on mode
    params =
      if socket.assigns.loadout_mode == :inline do
        Map.put(params, "file_path", "")
      else
        Map.put(params, "content", "")
      end

    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _loadout} ->
        loadouts = Loadout.list!()
        form = AshPhoenix.Form.for_create(Loadout, :create, as: "loadout") |> to_form()

        {:noreply,
         socket
         |> assign(:loadouts, loadouts)
         |> assign(:form, form)
         |> assign(:editing_loadout, nil)
         |> put_flash(:info, "Loadout saved")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def handle_event("edit_loadout", %{"id" => id}, socket) do
    case Loadout.get(id) do
      {:ok, loadout} ->
        form = AshPhoenix.Form.for_update(loadout, :update, as: "loadout") |> to_form()

        loadout_mode =
          if loadout.content && loadout.content != "" do
            :inline
          else
            :path
          end

        {:noreply,
         socket
         |> assign(:form, form)
         |> assign(:editing_loadout, loadout)
         |> assign(:loadout_mode, loadout_mode)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    form = AshPhoenix.Form.for_create(Loadout, :create, as: "loadout") |> to_form()

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:editing_loadout, nil)
     |> assign(:loadout_mode, :inline)}
  end

  @impl true
  def handle_event("delete_loadout", %{"id" => id}, socket) do
    case Loadout.get(id) do
      {:ok, loadout} ->
        Ash.destroy!(loadout)
        loadouts = Loadout.list!()

        {:noreply,
         socket
         |> assign(:loadouts, loadouts)
         |> put_flash(:info, "Loadout deleted")}

      {:error, _} ->
        {:noreply, socket}
    end
  end
end
