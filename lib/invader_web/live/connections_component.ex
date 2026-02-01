defmodule InvaderWeb.ConnectionsComponent do
  @moduledoc """
  LiveComponent for managing external service connections (GitHub, etc.).
  """
  use InvaderWeb, :live_component

  alias Invader.Connections.Connection
  alias Invader.Connections.GitHub.TokenGenerator
  alias Invader.Connections.Sprites.TokenProvider

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
                      <.type_icon type={connection.type} />
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
          <%= if @show_form do %>
            <div class="text-cyan-500 text-[10px] mb-3">
              {if @editing_connection, do: "EDIT CONNECTION", else: "ADD #{String.upcase(to_string(@selected_type))} CONNECTION"}
            </div>

            <.form
              for={@form}
              id="connection-form"
              phx-target={@myself}
              phx-change="validate"
              phx-submit="save_connection"
              class="space-y-4"
            >
              <input type="hidden" name={@form[:type].name} value={@selected_type} />

              <div class="space-y-2">
                <label class="text-cyan-500 text-[10px] block">NAME</label>
                <input
                  type="text"
                  name={@form[:name].name}
                  value={@form[:name].value}
                  placeholder={
                    if @selected_type == :sprites,
                      do: "My Sprites Connection",
                      else: "My GitHub Connection"
                  }
                  class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
                />
              </div>

              <%= if @selected_type == :github do %>
                <!-- GitHub Setup Instructions -->
                <div class="border border-cyan-800 p-3 bg-cyan-900/10">
                  <div class="text-cyan-400 text-[10px] mb-2 flex items-center gap-2">
                    <.setup_icon />
                    <span>GITHUB APP SETUP</span>
                  </div>
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
              <% else %>
                <!-- Sprites Setup Instructions -->
                <div class="border border-cyan-800 p-3 bg-cyan-900/10">
                  <div class="text-cyan-400 text-[10px] mb-2 flex items-center gap-2">
                    <.setup_icon />
                    <span>SPRITES SETUP</span>
                  </div>
                  <div class="text-cyan-600 text-[8px] space-y-1">
                    <p>
                      1.
                      <a
                        href="https://sprites.dev/account"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="text-cyan-400 underline hover:text-cyan-300"
                      >
                        Go to your Sprites account →
                      </a>
                    </p>
                    <p>2. Select your organization and generate a token</p>
                    <p>3. Copy and paste the token below</p>
                  </div>
                </div>

                <div class="space-y-2">
                  <label class="text-cyan-500 text-[10px] block">API TOKEN</label>
                  <input
                    type="password"
                    name={@form[:token].name}
                    value={@form[:token].value}
                    placeholder="spr_..."
                    class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none font-mono"
                  />
                </div>
              <% end %>

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
            <div class="text-cyan-500 text-[10px] mb-3">ADD CONNECTION</div>
            <div class="space-y-2">
              <%= if !@has_github do %>
                <button
                  phx-click="add_connection_type"
                  phx-value-type="github"
                  phx-target={@myself}
                  class="arcade-btn border-cyan-700 text-cyan-400 text-[10px] w-full py-3 hover:border-cyan-500 flex items-center justify-center gap-2"
                >
                  <.type_icon type={:github} />
                  <span>+ ADD GITHUB</span>
                </button>
              <% end %>
              <%= if !@has_sprites do %>
                <button
                  phx-click="add_connection_type"
                  phx-value-type="sprites"
                  phx-target={@myself}
                  class="arcade-btn border-cyan-700 text-cyan-400 text-[10px] w-full py-3 hover:border-cyan-500 flex items-center justify-center gap-2"
                >
                  <.type_icon type={:sprites} />
                  <span>+ ADD SPRITES</span>
                </button>
              <% end %>
              <%= if @has_github && @has_sprites do %>
                <p class="text-cyan-600 text-center py-4 text-[10px]">- ALL CONNECTIONS CONFIGURED -</p>
              <% end %>
            </div>
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

    # Check which connection types already exist
    existing_types = Enum.map(connections, & &1.type) |> MapSet.new()
    has_github = MapSet.member?(existing_types, :github)
    has_sprites = MapSet.member?(existing_types, :sprites)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:connections, connections)
     |> assign(:has_github, has_github)
     |> assign(:has_sprites, has_sprites)
     |> assign_new(:form, fn -> form end)
     |> assign_new(:show_form, fn -> false end)
     |> assign_new(:editing_connection, fn -> nil end)
     |> assign_new(:selected_type, fn -> :github end)}
  end

  @impl true
  def handle_event("add_connection_type", %{"type" => type}, socket) do
    form = AshPhoenix.Form.for_create(Connection, :create, as: "connection") |> to_form()
    selected_type = parse_type(type)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:form, form)
     |> assign(:selected_type, selected_type)}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    form = AshPhoenix.Form.for_create(Connection, :create, as: "connection") |> to_form()

    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:form, form)
     |> assign(:editing_connection, nil)
     |> assign(:selected_type, :github)}
  end

  @impl true
  def handle_event("validate", %{"connection" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    selected_type = parse_type(params["type"])
    {:noreply, socket |> assign(:form, to_form(form)) |> assign(:selected_type, selected_type)}
  end

  @impl true
  def handle_event("save_connection", %{"connection" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _connection} ->
        connections = Connection.list!()
        form = AshPhoenix.Form.for_create(Connection, :create, as: "connection") |> to_form()

        existing_types = Enum.map(connections, & &1.type) |> MapSet.new()

        {:noreply,
         socket
         |> assign(:connections, connections)
         |> assign(:has_github, MapSet.member?(existing_types, :github))
         |> assign(:has_sprites, MapSet.member?(existing_types, :sprites))
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
         |> assign(:show_form, true)
         |> assign(:selected_type, connection.type)}

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

        existing_types = Enum.map(connections, & &1.type) |> MapSet.new()

        {:noreply,
         socket
         |> assign(:connections, connections)
         |> assign(:has_github, MapSet.member?(existing_types, :github))
         |> assign(:has_sprites, MapSet.member?(existing_types, :sprites))
         |> put_flash(:info, "Connection deleted")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_connection", %{"id" => id}, socket) do
    case Connection.get(id) do
      {:ok, connection} ->
        result = test_connection_by_type(connection)

        case result do
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

  defp test_connection_by_type(%{type: :github} = connection) do
    TokenGenerator.test_connection(connection)
  end

  defp test_connection_by_type(%{type: :sprites} = connection) do
    TokenProvider.test_connection(connection)
  end

  defp test_connection_by_type(_connection) do
    {:error, :unsupported_connection_type}
  end

  defp parse_type("sprites"), do: :sprites
  defp parse_type(:sprites), do: :sprites
  defp parse_type(_), do: :github

  # 8-bit pixel art GitHub icon (octocat style)
  defp type_icon(%{type: :github} = assigns) do
    ~H"""
    <svg viewBox="0 0 16 16" class="w-5 h-5 fill-current text-cyan-400" style="image-rendering: pixelated;">
      <!-- Head/body circle -->
      <rect x="4" y="1" width="8" height="1" />
      <rect x="3" y="2" width="10" height="1" />
      <rect x="2" y="3" width="12" height="1" />
      <rect x="2" y="4" width="12" height="1" />
      <!-- Eyes -->
      <rect x="4" y="5" width="2" height="2" class="fill-black" />
      <rect x="10" y="5" width="2" height="2" class="fill-black" />
      <rect x="2" y="5" width="2" height="1" />
      <rect x="6" y="5" width="4" height="1" />
      <rect x="12" y="5" width="2" height="1" />
      <rect x="2" y="6" width="2" height="1" />
      <rect x="6" y="6" width="4" height="1" />
      <rect x="12" y="6" width="2" height="1" />
      <rect x="2" y="7" width="12" height="1" />
      <rect x="2" y="8" width="12" height="1" />
      <rect x="3" y="9" width="10" height="1" />
      <rect x="4" y="10" width="8" height="1" />
      <!-- Tentacles -->
      <rect x="2" y="10" width="2" height="1" />
      <rect x="12" y="10" width="2" height="1" />
      <rect x="1" y="11" width="2" height="2" />
      <rect x="13" y="11" width="2" height="2" />
      <rect x="5" y="11" width="2" height="1" />
      <rect x="9" y="11" width="2" height="1" />
      <rect x="6" y="12" width="4" height="2" />
    </svg>
    """
  end

  # 8-bit pixel art Sprites icon (Space Invader alien style)
  defp type_icon(%{type: :sprites} = assigns) do
    ~H"""
    <svg viewBox="0 0 11 8" class="w-5 h-5 fill-current text-green-400" style="image-rendering: pixelated;">
      <!-- Classic Space Invader shape -->
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

  # Fallback link icon
  defp type_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 16 16" class="w-5 h-5 fill-current text-cyan-400" style="image-rendering: pixelated;">
      <rect x="2" y="6" width="4" height="4" />
      <rect x="6" y="7" width="4" height="2" />
      <rect x="10" y="6" width="4" height="4" />
    </svg>
    """
  end

  # 8-bit pixel art setup/document icon
  defp setup_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 16 16" class="w-4 h-4 fill-current" style="image-rendering: pixelated;">
      <rect x="2" y="0" width="10" height="2" />
      <rect x="2" y="2" width="2" height="14" />
      <rect x="12" y="2" width="2" height="14" />
      <rect x="2" y="14" width="12" height="2" />
      <rect x="5" y="4" width="6" height="2" />
      <rect x="5" y="7" width="6" height="2" />
      <rect x="5" y="10" width="4" height="2" />
    </svg>
    """
  end

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
