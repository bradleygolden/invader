defmodule InvaderWeb.SpriteLive.Form do
  @moduledoc """
  LiveView for creating and editing sprites.
  """
  use InvaderWeb, :live_view

  alias Invader.Sprites.Sprite

  import InvaderWeb.PageLayout

  @impl true
  def mount(params, _session, socket) do
    action = if params["id"], do: :edit, else: :new

    socket =
      socket
      |> assign(:action, action)
      |> load_sprite(params)

    {:ok, socket}
  end

  defp load_sprite(socket, %{"id" => id}) do
    case Sprite.get(id) do
      {:ok, sprite} ->
        form = AshPhoenix.Form.for_update(sprite, :update, as: "sprite") |> to_form()

        socket
        |> assign(:page_title, "Edit Sprite")
        |> assign(:sprite, sprite)
        |> assign(:form, form)

      _ ->
        socket
        |> put_flash(:error, "Sprite not found")
        |> push_navigate(to: ~p"/")
    end
  end

  defp load_sprite(socket, _params) do
    form = AshPhoenix.Form.for_create(Sprite, :create, as: "sprite") |> to_form()

    socket
    |> assign(:page_title, "New Sprite")
    |> assign(:sprite, %Sprite{})
    |> assign(:form, form)
  end

  @impl true
  def handle_event("validate", %{"sprite" => sprite_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, sprite_params)
    {:noreply, assign(socket, :form, to_form(form))}
  end

  @impl true
  def handle_event("save", %{"sprite" => sprite_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: sprite_params) do
      {:ok, _sprite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sprite #{if socket.assigns.action == :new, do: "created", else: "updated"}")
         |> push_navigate(to: ~p"/")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def handle_event("delete_sprite", _params, socket) do
    sprite = socket.assigns.sprite

    case Invader.SpriteCli.Cli.destroy(sprite.name) do
      :ok ->
        Ash.destroy!(sprite)

        {:noreply,
         socket
         |> put_flash(:info, "Sprite deleted")
         |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete sprite: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.arcade_page page_title={if @action == :new, do: "NEW SPRITE", else: "EDIT SPRITE"}>
      <div>
        <.form
          for={@form}
          id="sprite-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
          autocomplete="off"
          data-1p-ignore
          data-lpignore="true"
        >
          <.input
            field={@form[:name]}
            type="text"
            label="NAME"
            placeholder="my-sprite"
            class="w-full bg-black border border-cyan-700 text-cyan-400 rounded px-3 py-2 focus:border-cyan-500 focus:outline-none"
            required
            autocomplete="off"
            data-1p-ignore
          />

          <.input
            field={@form[:org]}
            type="text"
            label="ORG (optional)"
            placeholder="organization"
            class="w-full bg-black border border-cyan-700 text-cyan-400 rounded px-3 py-2 focus:border-cyan-500 focus:outline-none"
            autocomplete="off"
            data-1p-ignore
          />

          <.input
            field={@form[:status]}
            type="select"
            label="STATUS"
            options={[
              {"Available", :available},
              {"Busy", :busy},
              {"Offline", :offline},
              {"Unknown", :unknown}
            ]}
            class="w-full bg-black border border-cyan-700 text-cyan-400 rounded px-3 py-2 focus:border-cyan-500 focus:outline-none"
          />

          <div class="flex justify-between mt-6 pt-4 border-t border-cyan-800">
            <div>
              <button
                :if={@action == :edit}
                type="button"
                phx-click="delete_sprite"
                data-confirm="Are you sure you want to delete this sprite?"
                class="px-4 py-2 border border-red-600 text-red-500 rounded hover:bg-red-900/30"
              >
                DELETE
              </button>
            </div>
            <div class="flex gap-3">
              <button
                type="submit"
                phx-disable-with="SAVING..."
                class="px-4 py-2 border border-cyan-600 text-cyan-400 rounded hover:bg-cyan-900/30"
              >
                {if @action == :new, do: "CREATE", else: "UPDATE"}
              </button>
            </div>
          </div>
        </.form>
      </div>
    </.arcade_page>
    """
  end
end
