defmodule InvaderWeb.ConnectionsLive do
  @moduledoc """
  LiveView for managing external service connections (GitHub, Sprites, etc.).
  """
  use InvaderWeb, :live_view

  alias Invader.Connections.Connection
  alias Invader.Connections.GitHub.TokenGenerator
  alias Invader.Connections.Sprites.TokenProvider
  alias Invader.Connections.Telegram.{ChatRegistration, Client}

  import InvaderWeb.PageLayout

  @impl true
  def mount(_params, _session, socket) do
    connections = Connection.list!()
    existing_types = Enum.map(connections, & &1.type) |> MapSet.new()

    {:ok,
     socket
     |> assign(:page_title, "Connections")
     |> assign(:connections, connections)
     |> assign(:has_github, MapSet.member?(existing_types, :github))
     |> assign(:has_sprites, MapSet.member?(existing_types, :sprites))
     |> assign(:has_telegram, MapSet.member?(existing_types, :telegram))
     |> assign(:show_form, false)
     |> assign(:selected_type, :github)
     |> assign(:editing_connection, nil)
     |> assign(:show_private_key_input, false)
     |> assign(:show_token_input, false)
     |> assign(:show_bot_token_input, false)
     |> assign(:telegram_registration, nil)
     |> assign(:app_url, InvaderWeb.Endpoint.url())
     |> assign(:form, new_form())}
  end

  @impl true
  def handle_params(%{"type" => type}, _url, socket) do
    selected_type = parse_type(type)
    form = new_form()

    {:noreply,
     socket
     |> assign(:page_title, "Add Connection")
     |> assign(:show_form, true)
     |> assign(:selected_type, selected_type)
     |> assign(:form, form)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  defp new_form do
    AshPhoenix.Form.for_create(Connection, :create, as: "connection") |> to_form()
  end

  @impl true
  def handle_event("add_connection_type", %{"type" => type}, socket) do
    form = new_form()
    selected_type = parse_type(type)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:form, form)
     |> assign(:selected_type, selected_type)}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:form, new_form())
     |> assign(:editing_connection, nil)
     |> assign(:selected_type, :github)
     |> assign(:show_private_key_input, false)
     |> assign(:show_token_input, false)
     |> assign(:show_bot_token_input, false)
     |> assign(:telegram_registration, nil)}
  end

  @impl true
  def handle_event("show_private_key_input", _params, socket) do
    {:noreply, assign(socket, :show_private_key_input, true)}
  end

  @impl true
  def handle_event("hide_private_key_input", _params, socket) do
    {:noreply, assign(socket, :show_private_key_input, false)}
  end

  @impl true
  def handle_event("show_token_input", _params, socket) do
    {:noreply, assign(socket, :show_token_input, true)}
  end

  @impl true
  def handle_event("hide_token_input", _params, socket) do
    {:noreply, assign(socket, :show_token_input, false)}
  end

  @impl true
  def handle_event("show_bot_token_input", _params, socket) do
    {:noreply, assign(socket, :show_bot_token_input, true)}
  end

  @impl true
  def handle_event("hide_bot_token_input", _params, socket) do
    {:noreply, assign(socket, :show_bot_token_input, false)}
  end

  @impl true
  def handle_event("connect_telegram", %{"id" => id}, socket) do
    case Connection.get(id) do
      {:ok, connection} ->
        case ChatRegistration.start_registration(connection) do
          {:ok, registration} ->
            form = AshPhoenix.Form.for_update(connection, :update, as: "connection") |> to_form()

            {:noreply,
             socket
             |> assign(:telegram_registration, registration)
             |> assign(:editing_connection, connection)
             |> assign(:form, form)
             |> assign(:show_form, true)
             |> assign(:selected_type, :telegram)
             |> put_flash(:info, "Click the link below to connect your Telegram")}

          {:error, {:invalid_token, reason}} ->
            {:noreply, put_flash(socket, :error, "Invalid bot token: #{inspect(reason)}")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to start registration: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_telegram_registration", _params, socket) do
    {:noreply, assign(socket, :telegram_registration, nil)}
  end

  @impl true
  def handle_event("validate", %{"connection" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    selected_type = parse_type(params["type"])
    {:noreply, socket |> assign(:form, to_form(form)) |> assign(:selected_type, selected_type)}
  end

  @impl true
  def handle_event("save_connection", %{"connection" => params}, socket) do
    params =
      if params["name"] == "" || params["name"] == nil do
        case params["type"] do
          "sprites" -> Map.put(params, "name", "Sprites")
          "github" -> Map.put(params, "name", "GitHub")
          "telegram" -> Map.put(params, "name", "Telegram")
          _ -> params
        end
      else
        params
      end

    params =
      if socket.assigns.editing_connection do
        params
        |> maybe_preserve_field("private_key", socket.assigns.editing_connection.private_key)
        |> maybe_preserve_field("token", socket.assigns.editing_connection.token)
        |> maybe_preserve_field(
          "telegram_bot_token",
          socket.assigns.editing_connection.telegram_bot_token
        )
      else
        params
      end

    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _connection} ->
        connections = Connection.list!()
        existing_types = Enum.map(connections, & &1.type) |> MapSet.new()

        {:noreply,
         socket
         |> assign(:connections, connections)
         |> assign(:has_github, MapSet.member?(existing_types, :github))
         |> assign(:has_sprites, MapSet.member?(existing_types, :sprites))
         |> assign(:has_telegram, MapSet.member?(existing_types, :telegram))
         |> assign(:form, new_form())
         |> assign(:show_form, false)
         |> assign(:editing_connection, nil)
         |> assign(:telegram_registration, nil)
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
         |> assign(:selected_type, connection.type)
         |> assign(:show_private_key_input, false)
         |> assign(:show_token_input, false)}

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
         |> assign(:has_telegram, MapSet.member?(existing_types, :telegram))
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
            {:ok, _updated} = Connection.update(connection, %{status: :connected})
            connections = Connection.list!()

            {:noreply,
             socket
             |> assign(:connections, connections)
             |> put_flash(:info, "Connection test successful!")}

          {:error, reason} ->
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

  defp test_connection_by_type(%{type: :telegram, telegram_bot_token: token})
       when is_binary(token) do
    case Client.get_me(token) do
      {:ok, _} -> {:ok, :connected}
      {:error, reason} -> {:error, reason}
    end
  end

  defp test_connection_by_type(%{type: :telegram}) do
    {:error, :missing_bot_token}
  end

  defp test_connection_by_type(_connection) do
    {:error, :unsupported_connection_type}
  end

  defp parse_type("sprites"), do: :sprites
  defp parse_type(:sprites), do: :sprites
  defp parse_type("telegram"), do: :telegram
  defp parse_type(:telegram), do: :telegram
  defp parse_type(_), do: :github

  defp maybe_preserve_field(params, field, existing_value) do
    if blank?(params[field]) && existing_value do
      Map.put(params, field, existing_value)
    else
      params
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""
  defp blank?(_), do: false

  defp key_fingerprint(private_key) when is_binary(private_key) do
    hash = :crypto.hash(:sha256, private_key) |> Base.encode16(case: :lower)
    "SHA256:#{String.slice(hash, 0, 16)}..."
  end

  defp key_fingerprint(_), do: "configured"

  defp token_preview(token) when is_binary(token) do
    if String.length(token) > 8 do
      "#{String.slice(token, 0, 8)}..."
    else
      "--------"
    end
  end

  defp token_preview(_), do: "configured"

  defp status_icon(:connected), do: "+"
  defp status_icon(:error), do: "x"
  defp status_icon(:pending), do: "o"
  defp status_icon(_), do: "?"

  defp status_class(:connected), do: "text-green-400"
  defp status_class(:error), do: "text-red-400"
  defp status_class(:pending), do: "text-yellow-400"
  defp status_class(_), do: "text-cyan-400"

  defp status_label(:connected), do: "CONNECTED"
  defp status_label(:error), do: "ERROR"
  defp status_label(:pending), do: "PENDING"
  defp status_label(_), do: "UNKNOWN"

  @impl true
  def render(assigns) do
    ~H"""
    <.arcade_page
      page_title={if @show_form && !@editing_connection, do: "ADD CONNECTION", else: "CONNECTIONS"}
      flash={@flash}
    >
      <div class="text-xs">
        <div class="space-y-4">
          <!-- Connections List -->
          <div :if={!@show_form} class="space-y-2 max-h-64 overflow-y-auto">
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
                        <span class="text-cyan-500">
                          [{String.upcase(to_string(connection.type))}]
                        </span>
                        <span class="ml-2">{status_label(connection.status)}</span>
                      </div>
                      <%= if connection.app_id do %>
                        <div class="text-cyan-700 text-[8px] mt-1 ml-6">
                          APP: {connection.app_id} | INSTALL: {connection.installation_id}
                        </div>
                      <% end %>
                      <%= if connection.type == :telegram && connection.telegram_chat_id do %>
                        <div class="text-cyan-700 text-[8px] mt-1 ml-6">
                          CHAT: {if connection.telegram_username,
                            do: "@#{connection.telegram_username}",
                            else: connection.telegram_chat_id}
                        </div>
                      <% end %>
                    </div>
                    <div class="flex gap-2 ml-2">
                      <%= if connection.type == :telegram && is_nil(connection.telegram_chat_id) && connection.telegram_bot_token do %>
                        <button
                          phx-click="connect_telegram"
                          phx-value-id={connection.id}
                          phx-disable-with="..."
                          class="arcade-btn border-blue-500 text-blue-400 text-[8px] py-1 px-2"
                        >
                          CONNECT
                        </button>
                      <% end %>
                      <button
                        phx-click="test_connection"
                        phx-value-id={connection.id}
                        phx-disable-with="TESTING..."
                        class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
                      >
                        TEST
                      </button>
                      <button
                        phx-click="edit_connection"
                        phx-value-id={connection.id}
                        class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
                      >
                        EDIT
                      </button>
                      <button
                        phx-click="delete_connection"
                        phx-value-id={connection.id}
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
          <div :if={@show_form} class="pt-4 border-t border-cyan-800">
            <div class="text-cyan-500 text-[10px] mb-3">
              {if @editing_connection,
                do: "EDIT CONNECTION",
                else: "ADD #{String.upcase(to_string(@selected_type))} CONNECTION"}
            </div>

            <.form
              for={@form}
              id="connection-form"
              phx-change="validate"
              phx-submit="save_connection"
              class="space-y-4"
            >
              <input type="hidden" name={@form[:type].name} value={@selected_type} />

              <%= cond do %>
                <% @selected_type == :github -> %>
                  <.github_form
                    form={@form}
                    editing_connection={@editing_connection}
                    show_private_key_input={@show_private_key_input}
                    app_url={@app_url}
                  />
                <% @selected_type == :telegram -> %>
                  <.telegram_form
                    form={@form}
                    editing_connection={@editing_connection}
                    show_bot_token_input={@show_bot_token_input}
                    telegram_registration={@telegram_registration}
                  />
                <% true -> %>
                  <.sprites_form
                    form={@form}
                    editing_connection={@editing_connection}
                    show_token_input={@show_token_input}
                  />
              <% end %>

              <div class="flex justify-end gap-3 pt-3">
                <button
                  type="button"
                  phx-click="cancel_form"
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
          </div>
          
    <!-- Add Connection Buttons -->
          <div :if={!@show_form} class="pt-4 border-t border-cyan-800">
            <div class="text-cyan-500 text-[10px] mb-3">ADD CONNECTION</div>
            <div class="space-y-2">
              <%= if !@has_github do %>
                <button
                  phx-click="add_connection_type"
                  phx-value-type="github"
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
                  class="arcade-btn border-cyan-700 text-cyan-400 text-[10px] w-full py-3 hover:border-cyan-500 flex items-center justify-center gap-2"
                >
                  <.type_icon type={:sprites} />
                  <span>+ ADD SPRITES</span>
                </button>
              <% end %>
              <%= if !@has_telegram do %>
                <button
                  phx-click="add_connection_type"
                  phx-value-type="telegram"
                  class="arcade-btn border-cyan-700 text-cyan-400 text-[10px] w-full py-3 hover:border-cyan-500 flex items-center justify-center gap-2"
                >
                  <.type_icon type={:telegram} />
                  <span>+ ADD TELEGRAM</span>
                </button>
              <% end %>
              <%= if @has_github && @has_sprites && @has_telegram do %>
                <p class="text-cyan-600 text-center py-4 text-[10px]">
                  - ALL CONNECTIONS CONFIGURED -
                </p>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </.arcade_page>
    """
  end

  defp github_form(assigns) do
    ~H"""
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
            Create a new GitHub App
          </a>
        </p>
        <p>2. Set Homepage URL to:</p>
        <div class="flex items-center gap-2 ml-3 my-1">
          <code class="bg-black/50 px-2 py-1 text-cyan-300 font-mono">{@app_url}</code>
          <button
            type="button"
            phx-hook="CopyToClipboard"
            id="copy-homepage-url"
            data-clipboard-text={@app_url}
            class="text-cyan-400 hover:text-cyan-300 text-[8px]"
            title="Copy to clipboard"
          >
            [COPY]
          </button>
        </div>
        <p>3. Under "Repository permissions", set:</p>
        <p class="ml-3">- Contents: Read & Write</p>
        <p class="ml-3">- Issues: Read & Write</p>
        <p class="ml-3">- Pull requests: Read & Write</p>
        <p class="ml-3">- Metadata: Read-only</p>
        <p>4. Uncheck "Webhook - Active"</p>
        <p>5. Create app, then generate private key (.pem file)</p>
        <p>6. Click "Install App" in sidebar, install on your account</p>
        <p class="ml-3 text-cyan-500">Installation ID is the number in URL after install:</p>
        <p class="ml-3 text-cyan-500">
          github.com/settings/installations/<span class="text-yellow-400">XXXXX</span>
        </p>
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
      <label class="text-cyan-500 text-[10px] block">
        INSTALLATION ID <span class="text-cyan-700">(optional)</span>
      </label>
      <input
        type="text"
        name={@form[:installation_id].name}
        value={@form[:installation_id].value}
        placeholder="12345678"
        class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
      />
      <div class="text-cyan-700 text-[8px]">
        Optional for multi-org: installation is auto-resolved from --repo flag.
        Only needed for commands without --repo (e.g., gh repo list).
      </div>
    </div>

    <div class="space-y-2">
      <label class="text-cyan-500 text-[10px] block">PRIVATE KEY (PEM)</label>
      <%= if @editing_connection && @editing_connection.private_key && !@show_private_key_input do %>
        <div class="border-2 border-green-700 bg-green-900/20 p-3">
          <div class="flex items-center gap-3">
            <.key_icon />
            <div class="flex-1">
              <div class="text-white text-[10px] font-medium">Private key</div>
              <div class="text-cyan-500 text-[8px] font-mono">
                {key_fingerprint(@editing_connection.private_key)}
              </div>
            </div>
            <button
              type="button"
              phx-click="show_private_key_input"
              class="arcade-btn border-cyan-600 text-cyan-400 text-[8px] py-1 px-2"
            >
              REPLACE
            </button>
          </div>
        </div>
      <% else %>
        <textarea
          name={@form[:private_key].name}
          placeholder="-----BEGIN RSA PRIVATE KEY-----&#10;...&#10;-----END RSA PRIVATE KEY-----"
          rows="6"
          class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none resize-none font-mono text-[10px]"
        ></textarea>
        <%= if @editing_connection && @editing_connection.private_key do %>
          <div class="flex items-center gap-2">
            <span class="text-cyan-700 text-[8px]">Leave blank to keep current key</span>
            <button
              type="button"
              phx-click="hide_private_key_input"
              class="text-cyan-500 hover:text-cyan-400 text-[8px]"
            >
              [CANCEL]
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp sprites_form(assigns) do
    ~H"""
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
            Go to your Sprites account
          </a>
        </p>
        <p>2. Select your organization and generate a token</p>
        <p>3. Copy and paste the token below</p>
      </div>
    </div>

    <div class="space-y-2">
      <label class="text-cyan-500 text-[10px] block">API TOKEN</label>
      <%= if @editing_connection && @editing_connection.token && !@show_token_input do %>
        <div class="border-2 border-green-700 bg-green-900/20 p-3">
          <div class="flex items-center gap-3">
            <.key_icon />
            <div class="flex-1">
              <div class="text-white text-[10px] font-medium">API Token</div>
              <div class="text-cyan-500 text-[8px] font-mono">
                {token_preview(@editing_connection.token)}
              </div>
            </div>
            <button
              type="button"
              phx-click="show_token_input"
              class="arcade-btn border-cyan-600 text-cyan-400 text-[8px] py-1 px-2"
            >
              REPLACE
            </button>
          </div>
        </div>
      <% else %>
        <input
          type="password"
          name={@form[:token].name}
          placeholder="spr_..."
          class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none font-mono"
        />
        <%= if @editing_connection && @editing_connection.token do %>
          <div class="flex items-center gap-2">
            <span class="text-cyan-700 text-[8px]">Leave blank to keep current token</span>
            <button
              type="button"
              phx-click="hide_token_input"
              class="text-cyan-500 hover:text-cyan-400 text-[8px]"
            >
              [CANCEL]
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp telegram_form(assigns) do
    ~H"""
    <div class="border border-cyan-800 p-3 bg-cyan-900/10">
      <div class="text-cyan-400 text-[10px] mb-2 flex items-center gap-2">
        <.setup_icon />
        <span>TELEGRAM BOT SETUP</span>
      </div>
      <div class="text-cyan-600 text-[8px] space-y-1">
        <p>
          1. Message
          <a
            href="https://t.me/BotFather"
            target="_blank"
            rel="noopener noreferrer"
            class="text-cyan-400 underline hover:text-cyan-300"
          >
            @BotFather
          </a>
          on Telegram
        </p>
        <p>2. Send <code class="bg-black/50 px-1 text-cyan-300">/newbot</code> and follow prompts</p>
        <p>3. Copy the bot token and paste it below</p>
        <p>4. After saving, click "CONNECT" to link your chat</p>
      </div>
    </div>

    <div class="space-y-2">
      <label class="text-cyan-500 text-[10px] block">BOT TOKEN</label>
      <%= if @editing_connection && @editing_connection.telegram_bot_token && !@show_bot_token_input do %>
        <div class="border-2 border-green-700 bg-green-900/20 p-3">
          <div class="flex items-center gap-3">
            <.key_icon />
            <div class="flex-1">
              <div class="text-white text-[10px] font-medium">Bot Token</div>
              <div class="text-cyan-500 text-[8px] font-mono">
                {token_preview(@editing_connection.telegram_bot_token)}
              </div>
            </div>
            <button
              type="button"
              phx-click="show_bot_token_input"
              class="arcade-btn border-cyan-600 text-cyan-400 text-[8px] py-1 px-2"
            >
              REPLACE
            </button>
          </div>
        </div>
      <% else %>
        <input
          type="password"
          name={@form[:telegram_bot_token].name}
          placeholder="123456789:ABCdefGHIjklMNOpqrSTUvwxYZ"
          class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none font-mono"
        />
        <%= if @editing_connection && @editing_connection.telegram_bot_token do %>
          <div class="flex items-center gap-2">
            <span class="text-cyan-700 text-[8px]">Leave blank to keep current token</span>
            <button
              type="button"
              phx-click="hide_bot_token_input"
              class="text-cyan-500 hover:text-cyan-400 text-[8px]"
            >
              [CANCEL]
            </button>
          </div>
        <% end %>
      <% end %>
    </div>

    <%= if @editing_connection && @editing_connection.telegram_chat_id do %>
      <div class="border-2 border-green-700 bg-green-900/20 p-3">
        <div class="flex items-center gap-3">
          <.telegram_icon />
          <div class="flex-1">
            <div class="text-white text-[10px] font-medium">Chat Connected</div>
            <div class="text-cyan-500 text-[8px]">
              <%= if @editing_connection.telegram_username do %>
                @{@editing_connection.telegram_username}
              <% else %>
                Chat ID: {@editing_connection.telegram_chat_id}
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% else %>
      <%= if @editing_connection && @telegram_registration do %>
        <div class="border-2 border-yellow-700 bg-yellow-900/20 p-3">
          <div class="text-yellow-400 text-[10px] mb-2">CONNECT YOUR TELEGRAM</div>
          <div class="text-cyan-600 text-[8px] space-y-2">
            <p>Click the link below to open Telegram and connect:</p>
            <a
              href={@telegram_registration.link}
              target="_blank"
              rel="noopener noreferrer"
              class="block bg-black/50 px-3 py-2 text-cyan-300 font-mono text-[10px] hover:text-cyan-200 break-all"
            >
              {@telegram_registration.link}
            </a>
            <p class="text-cyan-700">
              Or search for @{@telegram_registration.bot_username} and send the start command
            </p>
          </div>
          <button
            type="button"
            phx-click="clear_telegram_registration"
            class="text-cyan-500 hover:text-cyan-400 text-[8px] mt-2"
          >
            [CANCEL]
          </button>
        </div>
      <% else %>
        <%= if @editing_connection && @editing_connection.telegram_bot_token do %>
          <div class="border border-cyan-800 p-3">
            <div class="text-cyan-600 text-[8px]">
              Save the connection first, then click "CONNECT" to link your Telegram chat.
            </div>
          </div>
        <% end %>
      <% end %>
    <% end %>
    """
  end

  defp type_icon(%{type: :github} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 16 16"
      class="w-5 h-5 fill-current text-cyan-400"
      style="image-rendering: pixelated;"
    >
      <rect x="4" y="1" width="8" height="1" />
      <rect x="3" y="2" width="10" height="1" />
      <rect x="2" y="3" width="12" height="1" />
      <rect x="2" y="4" width="12" height="1" />
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

  defp type_icon(%{type: :sprites} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 11 8"
      class="w-5 h-5 fill-current text-green-400"
      style="image-rendering: pixelated;"
    >
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

  defp type_icon(%{type: :telegram} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 16 16"
      class="w-5 h-5"
      style="image-rendering: pixelated;"
    >
      <!-- Paper airplane pointing upper-right like Telegram logo -->
      <!-- Main body -->
      <rect x="1" y="8" width="2" height="1" class="fill-blue-400" />
      <rect x="2" y="7" width="2" height="1" class="fill-blue-400" />
      <rect x="3" y="6" width="3" height="1" class="fill-blue-400" />
      <rect x="4" y="5" width="4" height="1" class="fill-blue-400" />
      <rect x="5" y="4" width="5" height="1" class="fill-blue-400" />
      <rect x="6" y="3" width="6" height="1" class="fill-blue-400" />
      <rect x="7" y="2" width="6" height="1" class="fill-blue-400" />
      <rect x="8" y="1" width="6" height="1" class="fill-blue-400" />
      <!-- Bottom wing -->
      <rect x="3" y="9" width="2" height="1" class="fill-blue-300" />
      <rect x="4" y="10" width="2" height="1" class="fill-blue-300" />
      <rect x="5" y="11" width="2" height="1" class="fill-blue-300" />
      <!-- Fold/tail going down -->
      <rect x="6" y="8" width="1" height="1" class="fill-blue-200" />
      <rect x="7" y="9" width="1" height="2" class="fill-blue-200" />
      <rect x="8" y="11" width="1" height="2" class="fill-blue-200" />
    </svg>
    """
  end

  defp type_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 16 16"
      class="w-5 h-5 fill-current text-cyan-400"
      style="image-rendering: pixelated;"
    >
      <rect x="2" y="6" width="4" height="4" />
      <rect x="6" y="7" width="4" height="2" />
      <rect x="10" y="6" width="4" height="4" />
    </svg>
    """
  end

  defp telegram_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 16 16"
      class="w-6 h-6"
      style="image-rendering: pixelated;"
    >
      <!-- Paper airplane pointing upper-right like Telegram logo -->
      <!-- Main body -->
      <rect x="1" y="8" width="2" height="1" class="fill-blue-400" />
      <rect x="2" y="7" width="2" height="1" class="fill-blue-400" />
      <rect x="3" y="6" width="3" height="1" class="fill-blue-400" />
      <rect x="4" y="5" width="4" height="1" class="fill-blue-400" />
      <rect x="5" y="4" width="5" height="1" class="fill-blue-400" />
      <rect x="6" y="3" width="6" height="1" class="fill-blue-400" />
      <rect x="7" y="2" width="6" height="1" class="fill-blue-400" />
      <rect x="8" y="1" width="6" height="1" class="fill-blue-400" />
      <!-- Bottom wing -->
      <rect x="3" y="9" width="2" height="1" class="fill-blue-300" />
      <rect x="4" y="10" width="2" height="1" class="fill-blue-300" />
      <rect x="5" y="11" width="2" height="1" class="fill-blue-300" />
      <!-- Fold/tail going down -->
      <rect x="6" y="8" width="1" height="1" class="fill-blue-200" />
      <rect x="7" y="9" width="1" height="2" class="fill-blue-200" />
      <rect x="8" y="11" width="1" height="2" class="fill-blue-200" />
    </svg>
    """
  end

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

  defp key_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 16 16"
      class="w-6 h-6 fill-current text-green-400"
      style="image-rendering: pixelated;"
    >
      <rect x="0" y="6" width="8" height="4" />
      <rect x="8" y="5" width="2" height="6" />
      <rect x="10" y="4" width="2" height="8" />
      <rect x="12" y="5" width="2" height="6" />
      <rect x="14" y="6" width="2" height="4" />
      <rect x="2" y="10" width="2" height="2" />
      <rect x="5" y="10" width="2" height="2" />
    </svg>
    """
  end
end
