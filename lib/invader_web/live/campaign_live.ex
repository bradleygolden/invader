defmodule InvaderWeb.CampaignLive do
  @moduledoc """
  Campaign list and management page.
  """
  use InvaderWeb, :live_view

  alias Invader.Campaigns.Campaign

  @impl true
  def mount(_params, _session, socket) do
    campaigns = Campaign.list!() |> Ash.load!([:nodes, :runs])

    socket =
      socket
      |> assign(:page_title, "Campaigns")
      |> assign(:campaigns, campaigns)
      |> assign(:campaign, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Campaigns")
    |> assign(:campaign, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Campaign")
    |> assign(:campaign, %Campaign{})
  end

  @impl true
  def handle_event("create_campaign", %{"name" => name, "description" => description}, socket) do
    case Campaign.create(%{name: name, description: description}) do
      {:ok, campaign} ->
        {:noreply, push_navigate(socket, to: ~p"/workflows/#{campaign.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create campaign")}
    end
  end

  @impl true
  def handle_event("delete_campaign", %{"id" => id}, socket) do
    case Campaign.get(id) do
      {:ok, campaign} ->
        Ash.destroy!(campaign)
        campaigns = Enum.reject(socket.assigns.campaigns, &(&1.id == id))
        {:noreply, assign(socket, :campaigns, campaigns)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("archive_campaign", %{"id" => id}, socket) do
    case Campaign.get(id) do
      {:ok, campaign} ->
        case Campaign.update(campaign, %{status: :archived}) do
          {:ok, updated} ->
            campaigns = update_campaign_in_list(socket.assigns.campaigns, updated)
            {:noreply, assign(socket, :campaigns, campaigns)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to archive campaign")}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("activate_campaign", %{"id" => id}, socket) do
    case Campaign.get(id) do
      {:ok, campaign} ->
        case Campaign.update(campaign, %{status: :active}) do
          {:ok, updated} ->
            campaigns = update_campaign_in_list(socket.assigns.campaigns, updated)
            {:noreply, assign(socket, :campaigns, campaigns)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to activate campaign")}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp update_campaign_in_list(campaigns, updated) do
    Enum.map(campaigns, fn c ->
      if c.id == updated.id, do: updated, else: c
    end)
  end

  defp status_class(:draft), do: "text-yellow-400 border-yellow-500"
  defp status_class(:active), do: "text-green-400 border-green-500"
  defp status_class(:archived), do: "text-cyan-600 border-cyan-700"
  defp status_class(_), do: "text-cyan-400 border-cyan-500"

  defp status_label(:draft), do: "DRAFT"
  defp status_label(:active), do: "ACTIVE"
  defp status_label(:archived), do: "ARCHIVED"
  defp status_label(status), do: status |> to_string() |> String.upcase()

  @impl true
  def render(assigns) do
    ~H"""
    <main
      class="arcade-container min-h-screen bg-black p-2 sm:p-4 relative z-10"
      role="main"
    >
      <div class="crt-overlay pointer-events-none fixed inset-0 z-40" aria-hidden="true"></div>
      
    <!-- New Campaign Modal -->
      <.modal
        :if={@live_action == :new}
        id="new-campaign-modal"
        show
        on_cancel={JS.patch(~p"/workflows")}
      >
        <:title>NEW CAMPAIGN</:title>
        <form phx-submit="create_campaign" class="space-y-4">
          <div>
            <label class="block text-[10px] text-cyan-500 mb-2">NAME</label>
            <input
              type="text"
              name="name"
              required
              class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
              placeholder="My Campaign"
            />
          </div>
          <div>
            <label class="block text-[10px] text-cyan-500 mb-2">DESCRIPTION</label>
            <textarea
              name="description"
              rows="3"
              class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none"
              placeholder="Optional description..."
            ></textarea>
          </div>
          <div class="flex justify-end gap-2 pt-4">
            <.link
              patch={~p"/workflows"}
              class="arcade-btn border-cyan-700 text-cyan-500 text-[10px]"
            >
              CANCEL
            </.link>
            <button type="submit" class="arcade-btn border-green-500 text-green-400 text-[10px]">
              CREATE
            </button>
          </div>
        </form>
      </.modal>
      
    <!-- Header -->
      <header class="flex items-center justify-between mb-6">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/"} class="text-cyan-500 hover:text-cyan-400 text-xs">
            ← DASHBOARD
          </.link>
          <h1 class="text-xl text-cyan-400 arcade-glow tracking-wider">
            CAMPAIGNS
          </h1>
        </div>

        <.link
          patch={~p"/workflows/new"}
          class="arcade-btn border-green-500 text-green-400 text-[10px]"
        >
          + NEW CAMPAIGN
        </.link>
      </header>
      
    <!-- Campaigns grid -->
      <%= if Enum.empty?(@campaigns) do %>
        <div class="arcade-panel p-8 text-center">
          <p class="text-cyan-600 text-[10px] mb-4">- NO CAMPAIGNS -</p>
          <p class="text-cyan-700 text-[8px] mb-6">
            Create campaigns to orchestrate multiple missions
          </p>
          <.link
            patch={~p"/workflows/new"}
            class="arcade-btn border-cyan-500 text-cyan-400 text-[10px]"
          >
            + CREATE FIRST CAMPAIGN
          </.link>
        </div>
      <% else %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for campaign <- @campaigns do %>
            <div class={"arcade-panel p-4 #{status_class(campaign.status)}"}>
              <div class="flex items-start justify-between mb-3">
                <div>
                  <h3 class="text-white text-xs mb-1">{campaign.name}</h3>
                  <span class={"text-[8px] #{status_class(campaign.status)}"}>
                    {status_label(campaign.status)}
                  </span>
                </div>
                <div class="flex gap-1">
                  <.link
                    navigate={~p"/workflows/#{campaign.id}"}
                    class="arcade-btn border-cyan-500 text-cyan-400 text-[8px] py-1 px-2"
                  >
                    EDIT
                  </.link>
                </div>
              </div>

              <%= if campaign.description do %>
                <p class="text-[8px] text-cyan-600 mb-3 line-clamp-2">
                  {campaign.description}
                </p>
              <% end %>

              <div class="flex items-center justify-between text-[8px] text-cyan-700 border-t border-cyan-800 pt-3 mt-3">
                <span>{length(campaign.nodes)} NODES</span>
                <span>{length(campaign.runs)} RUNS</span>
              </div>

              <div class="flex gap-1 mt-3">
                <%= if campaign.status == :archived do %>
                  <button
                    phx-click="activate_campaign"
                    phx-value-id={campaign.id}
                    class="arcade-btn border-green-500 text-green-400 text-[8px] py-1 px-2 flex-1"
                  >
                    ACTIVATE
                  </button>
                <% else %>
                  <button
                    phx-click="archive_campaign"
                    phx-value-id={campaign.id}
                    class="arcade-btn border-yellow-500 text-yellow-400 text-[8px] py-1 px-2 flex-1"
                  >
                    ARCHIVE
                  </button>
                <% end %>
                <button
                  phx-click="delete_campaign"
                  phx-value-id={campaign.id}
                  data-confirm="Delete this campaign? This cannot be undone."
                  class="arcade-btn border-red-500 text-red-400 text-[8px] py-1 px-2"
                >
                  DELETE
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </main>
    """
  end
end
