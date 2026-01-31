defmodule InvaderWeb.SpriteFormComponent do
  @moduledoc """
  LiveComponent for creating and editing sprites.
  """
  use InvaderWeb, :live_component

  alias Invader.Sprites.Sprite

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="sprite-form"
        phx-target={@myself}
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
          class="w-full bg-black border border-green-700 text-green-400 rounded px-3 py-2 focus:border-green-500 focus:outline-none"
          required
          autocomplete="off"
          data-1p-ignore
        />

        <.input
          field={@form[:org]}
          type="text"
          label="ORG (optional)"
          placeholder="organization"
          class="w-full bg-black border border-green-700 text-green-400 rounded px-3 py-2 focus:border-green-500 focus:outline-none"
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
          class="w-full bg-black border border-green-700 text-green-400 rounded px-3 py-2 focus:border-green-500 focus:outline-none"
        />

        <div class="flex justify-between mt-6 pt-4 border-t border-green-800">
          <div>
            <button
              :if={@action == :edit}
              type="button"
              phx-click="delete_sprite"
              phx-value-id={@sprite.id}
              data-confirm="Are you sure you want to delete this sprite?"
              class="px-4 py-2 border border-red-600 text-red-500 rounded hover:bg-red-900/30"
            >
              DELETE
            </button>
          </div>
          <div class="flex gap-3">
            <.link
              patch={~p"/"}
              class="px-4 py-2 border border-green-700 text-green-600 rounded hover:bg-green-900/30"
            >
              CANCEL
            </.link>
            <button
              type="submit"
              phx-disable-with="SAVING..."
              class="px-4 py-2 border border-green-600 text-green-400 rounded hover:bg-green-900/30"
            >
              {(@action == :new && "CREATE") || "UPDATE"}
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{sprite: sprite, action: action} = assigns, socket) do
    form =
      if action == :new do
        AshPhoenix.Form.for_create(Sprite, :create, as: "sprite")
      else
        AshPhoenix.Form.for_update(sprite, :update, as: "sprite")
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(form))}
  end

  @impl true
  def handle_event("validate", %{"sprite" => sprite_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, sprite_params)
    {:noreply, assign(socket, :form, to_form(form))}
  end

  @impl true
  def handle_event("save", %{"sprite" => sprite_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: sprite_params) do
      {:ok, sprite} ->
        notify_parent({:saved, sprite})

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Sprite #{(socket.assigns.action == :new && "created") || "updated"}"
         )
         |> push_patch(to: ~p"/")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
