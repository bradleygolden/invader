defmodule InvaderWeb.ConnectionsComponent do
  @moduledoc """
  LiveComponent for managing external service connections (GitHub, etc.).
  """
  use InvaderWeb, :live_component

  alias Invader.Connections.Connection
  alias Invader.Connections.GitHub.TokenGenerator

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <div class="space-y-4">
        <!-- Connections List -->
        <div class="space-y-2 max-h-64 overflow-y-auto">
          <%= if Enum.empty?(@connections) do %>
            <p class="text-cyan-600 text-center py-4 text-[10px]">- NO CONNECTIONS -</p>
          <% else %>
            <%= for connection <- @connections do %>
              <div class="border border-cyan-800 p-3 hover:bg-cyan-900/10 transition-colors">
                <div class="flex justify-between items-start">
                  <div class="flex-1">
                    <div class="flex items-center gap-2">
                      <span class="text-lg">{type_icon(connection.type)}</span>
                      <span class="text-white text-xs font-medium">{connection.name}</span>
                      <span class={status_class(connection.status)}>
                        {status_icon(connection.status)}
                      </span>
                    </div>
                    <div class="text-cyan-600 text-[8px] mt-1 ml-6">
                      <span class="text-cyan-500">[{String.upcase(to_string(connection.type))}]</span>
                      <span class="ml-2">{status_label(connection.status)}</span>
                    </div>
                    <%= if connection.app_id do %>
                      <div class="text-cyan-700 text-[8px] mt-1 ml-6">
                        APP: {connection.app_id} | INSTALL: {connection.installation_id}
                      </div>
                    <% end %>
                  </div>
                  <div class="flex gap-2 ml-2">
                    <button
                      phx-click="test_connection"
                      phx-value-id={connection.id}
                      phx-target={@myself}
                      class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
                    >
                      TEST
                    </button>
                    <button
                      phx-click="edit_connection"
                      phx-value-id={connection.id}
                      phx-target={@myself}
                      class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
                    >
                      EDIT
                    </button>
                    <button
                      phx-click="delete_connection"
                      phx-value-id={connection.id}
                      phx-target={@myself}
                      data-confirm="Delete this connection?"
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
        
    <!-- Add/Edit Connection Form -->
        <div class="pt-4 border-t border-cyan-800">
          <div class="text-cyan-500 text-[10px] mb-3">
            {if @editing_connection, do: "EDIT CONNECTION", else: "ADD CONNECTION"}
          </div>

          <%= if @show_form do %>
            <.form
              for={@form}
              id="connection-form"
              phx-target={@myself}
              phx-change="validate"
              phx-submit="save_connection"
              class="space-y-4"
            >
              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">TYPE</label>
                <select
                  name={@form[:type].name}
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                  disabled={@editing_connection != nil}
                >
                  <option
                    value="github"
                    selected={@form[:type].value == :github || @form[:type].value == "github"}
                  >
                    🐙 GitHub
                  </option>
                </select>
              </div>

              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">NAME</label>
                <input
                  type="text"
                  name={@form[:name].name}
                  value={@form[:name].value}
                  placeholder="My GitHub Connection"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
              </div>
              
    <!-- GitHub Setup Instructions -->
              <div class="border border-cyan-800 p-3 bg-cyan-900/10">
                <div class="text-cyan-400 text-[10px] mb-2">📋 GITHUB APP SETUP</div>
                <div class="text-cyan-600 text-[8px] space-y-1">
                  <p>
                    1.
                    <a
                      href="https://github.com/settings/apps/new"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-cyan-400 underline hover:text-cyan-300"
                    >
                      Create a new GitHub App →
                    </a>
                  </p>
                  <p>2. Set these permissions:</p>
                  <p class="ml-3">• Contents (Read & Write)</p>
                  <p class="ml-3">• Issues (Read & Write)</p>
                  <p class="ml-3">• Pull requests (Read & Write)</p>
                  <p class="ml-3">• Metadata (Read-only)</p>
                  <p>3. Uncheck "Webhook → Active"</p>
                  <p>4. Create app, then generate private key (.pem file)</p>
                  <p>5. Install app on your repos (note Installation ID from URL)</p>
                  <p>6. Copy App ID, Installation ID, and private key below</p>
                </div>
              </div>

              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">APP ID</label>
                <input
                  type="text"
                  name={@form[:app_id].name}
                  value={@form[:app_id].value}
                  placeholder="123456"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
              </div>

              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">INSTALLATION ID</label>
                <input
                  type="text"
                  name={@form[:installation_id].name}
                  value={@form[:installation_id].value}
                  placeholder="12345678"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
                <div class="text-cyan-700 text-[8px]">
                  Find in URL: github.com/settings/installations/XXXXX
                </div>
              </div>

              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">PRIVATE KEY (PEM)</label>
                <textarea
                  name={@form[:private_key].name}
                  placeholder="-----BEGIN RSA PRIVATE KEY-----&#10;...&#10;-----END RSA PRIVATE KEY-----"
                  rows="6"
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none resize-none font-mono text-[10px]"
                >{@form[:private_key].value}</textarea>
              </div>

              <div class="flex justify-end gap-3 pt-3">
                <button
                  type="button"
                  phx-click="cancel_form"
                  phx-target={@myself}
                  class="arcade-btn border-cyan-600 text-cyan-400 text-[10px]"
                >
                  CANCEL
                </button>
                <button
                  type="submit"
                  phx-disable-with="SAVING..."
                  class="arcade-btn border-green-500 text-green-400 text-[10px]"
                >
                  {if @editing_connection, do: "UPDATE", else: "CREATE"}
                </button>
              </div>
            </.form>
          <% else %>
            <button
              phx-click="show_form"
              phx-target={@myself}
              class="arcade-btn border-green-500 text-green-400 text-[10px] w-full py-3"
            >
              + ADD GITHUB CONNECTION
            </button>
          <% end %>
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
    connections = Connection.list!()

    form =
      if socket.assigns[:editing_connection] do
        socket.assigns.form
      else
        AshPhoenix.Form.for_create(Connection, :create, as: "connection") |> to_form()
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:connections, connections)
     |> assign_new(:form, fn -> form end)
     |> assign_new(:show_form, fn -> false end)
     |> assign_new(:editing_connection, fn -> nil end)}
  end

  @impl true
  def handle_event("show_form", _params, socket) do
    form = AshPhoenix.Form.for_create(Connection, :create, as: "connection") |> to_form()
    {:noreply, socket |> assign(:show_form, true) |> assign(:form, form)}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    form = AshPhoenix.Form.for_create(Connection, :create, as: "connection") |> to_form()

    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:form, form)
     |> assign(:editing_connection, nil)}
  end

  @impl true
  def handle_event("validate", %{"connection" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, :form, to_form(form))}
  end

  @impl true
  def handle_event("save_connection", %{"connection" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _connection} ->
        connections = Connection.list!()
        form = AshPhoenix.Form.for_create(Connection, :create, as: "connection") |> to_form()

        {:noreply,
         socket
         |> assign(:connections, connections)
         |> assign(:form, form)
         |> assign(:show_form, false)
         |> assign(:editing_connection, nil)
         |> put_flash(:info, "Connection saved")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def handle_event("edit_connection", %{"id" => id}, socket) do
    case Connection.get(id) do
      {:ok, connection} ->
        form = AshPhoenix.Form.for_update(connection, :update, as: "connection") |> to_form()

        {:noreply,
         socket
         |> assign(:form, form)
         |> assign(:editing_connection, connection)
         |> assign(:show_form, true)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_connection", %{"id" => id}, socket) do
    case Connection.get(id) do
      {:ok, connection} ->
        Ash.destroy!(connection)
        connections = Connection.list!()

        {:noreply,
         socket
         |> assign(:connections, connections)
         |> put_flash(:info, "Connection deleted")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_connection", %{"id" => id}, socket) do
    case Connection.get(id) do
      {:ok, connection} ->
        case TokenGenerator.test_connection(connection) do
          {:ok, :connected} ->
            # Update status to connected
            {:ok, _updated} = Connection.update(connection, %{status: :connected})
            connections = Connection.list!()

            {:noreply,
             socket
             |> assign(:connections, connections)
             |> put_flash(:info, "Connection test successful!")}

          {:error, reason} ->
            # Update status to error
            {:ok, _updated} = Connection.update(connection, %{status: :error})
            connections = Connection.list!()

            {:noreply,
             socket
             |> assign(:connections, connections)
             |> put_flash(:error, "Connection test failed: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp type_icon(:github), do: "🐙"
  defp type_icon(_), do: "🔗"

  defp status_icon(:connected), do: "✓"
  defp status_icon(:error), do: "✗"
  defp status_icon(:pending), do: "○"
  defp status_icon(_), do: "?"

  defp status_class(:connected), do: "text-green-400"
  defp status_class(:error), do: "text-red-400"
  defp status_class(:pending), do: "text-yellow-400"
  defp status_class(_), do: "text-cyan-400"

  defp status_label(:connected), do: "CONNECTED"
  defp status_label(:error), do: "ERROR"
  defp status_label(:pending), do: "PENDING"
  defp status_label(_), do: "UNKNOWN"
end
