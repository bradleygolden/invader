defmodule Invader.Workers.SpriteProvisioner do
  @moduledoc """
  Oban worker that creates sprites for missions asynchronously.

  When a mission is created with `create_with_sprite`, this worker:
  1. Creates the sprite via the Sprites SDK
  2. Creates a local Sprite record (with org fetched from API)
  3. Links the sprite to the mission (transitions to :setup)
  4. Injects agent config (API keys) into the sprite
  5. Completes setup (transitions to :pending)
  """
  use Oban.Worker,
    queue: :sprites,
    max_attempts: 3

  require Logger

  alias Invader.Missions.Mission
  alias Invader.Sprites.Sprite
  alias Invader.SpriteCli.Cli

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"mission_id" => mission_id}}) do
    Logger.info("Starting sprite provisioning for mission #{mission_id}")

    with {:ok, mission} <- Mission.get(mission_id),
         :ok <- validate_can_provision(mission),
         {:ok, _sprite} <- create_sprite(mission),
         {:ok, sprite_record} <- create_sprite_record(mission),
         {:ok, updated_mission} <- link_sprite_to_mission(mission, sprite_record),
         :ok <- inject_agent_config(updated_mission),
         {:ok, _mission} <- complete_setup(updated_mission) do
      Logger.info(
        "Sprite #{mission.sprite_name} provisioned and configured for mission #{mission_id}"
      )

      :ok
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        Logger.error("Mission #{mission_id} not found during sprite provisioning")
        {:error, :mission_not_found}

      {:error, :invalid_status} ->
        Logger.warning("Mission #{mission_id} is not in provisioning state, skipping")
        :ok

      {:error, reason} ->
        Logger.error("Sprite provisioning failed for mission #{mission_id}: #{inspect(reason)}")
        handle_provision_failure(mission_id, reason)
        {:error, reason}
    end
  end

  defp validate_can_provision(%Mission{status: :provisioning}), do: :ok
  defp validate_can_provision(_mission), do: {:error, :invalid_status}

  defp create_sprite(%Mission{sprite_name: name}) do
    Logger.info("Creating sprite: #{name}")

    case Cli.create(name) do
      {:ok, sprite} ->
        Logger.info("Sprite #{name} created on sprites.dev")
        {:ok, sprite}

      {:error, {:api_error, 409, _}} ->
        # Sprite already exists on sprites.dev, that's fine
        Logger.info("Sprite #{name} already exists on sprites.dev, continuing")
        {:ok, %{name: name}}

      {:error, reason} ->
        Logger.error("Failed to create sprite #{name}: #{inspect(reason)}")
        {:error, {:sprite_creation_failed, reason}}
    end
  end

  defp create_sprite_record(%Mission{sprite_name: name}) do
    Logger.info("Creating local sprite record for #{name}")

    # Fetch sprite info from sprites.dev to get the org
    org = fetch_sprite_org(name)

    case Sprite.create(%{name: name, org: org, status: :available}) do
      {:ok, sprite} ->
        {:ok, sprite}

      {:error, _error} ->
        # Sprite record might already exist, try to fetch it
        case Sprite.get_by_name(name) do
          {:ok, sprite} ->
            # Update org if it's missing
            if is_nil(sprite.org) and org do
              Logger.info("Updating org for existing sprite #{name}")
              Sprite.update(sprite, %{org: org})
            else
              Logger.info("Sprite record already exists for #{name}")
              {:ok, sprite}
            end

          error ->
            error
        end
    end
  end

  defp fetch_sprite_org(name) do
    case Cli.get_info(name) do
      {:ok, info} ->
        org = info[:organization] || info["organization"]
        Logger.info("Fetched org '#{org}' for sprite #{name}")
        org

      {:error, reason} ->
        Logger.warning("Could not fetch sprite info for #{name}: #{inspect(reason)}")
        nil
    end
  end

  defp link_sprite_to_mission(mission, sprite) do
    Logger.info("Linking sprite #{sprite.name} to mission #{mission.id}")
    Mission.sprite_ready(mission, %{sprite_id: sprite.id})
  end

  defp inject_agent_config(%Mission{sprite_name: sprite_name, agent_provider: nil}) do
    Logger.info(
      "No agent provider configured for sprite #{sprite_name}, skipping config injection"
    )

    :ok
  end

  defp inject_agent_config(%Mission{
         sprite_name: sprite_name,
         agent_provider: provider,
         agent_api_key: api_key,
         agent_base_url: base_url
       }) do
    Logger.info("Injecting agent config for provider #{provider} into sprite #{sprite_name}")

    opts = if base_url, do: [base_url: base_url], else: []

    case Cli.inject_agent_config(sprite_name, provider, api_key, opts) do
      {:ok, _output} ->
        Logger.info("Agent config injected successfully for sprite #{sprite_name}")
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to inject agent config for sprite #{sprite_name}: #{inspect(reason)}"
        )

        {:error, {:agent_config_failed, reason}}
    end
  end

  defp complete_setup(mission) do
    Logger.info("Completing setup for mission #{mission.id}")
    Mission.setup_complete(mission)
  end

  defp handle_provision_failure(mission_id, reason) do
    case Mission.get(mission_id) do
      {:ok, mission} ->
        error_message = format_error(reason)
        Mission.provision_failed(mission, %{error_message: error_message})

      _ ->
        :ok
    end
  end

  defp format_error({:sprite_creation_failed, reason}),
    do: "Sprite creation failed: #{inspect(reason)}"

  defp format_error(reason), do: "Provisioning failed: #{inspect(reason)}"

  @doc """
  Enqueues a mission for sprite provisioning.
  """
  def enqueue(mission_id) do
    %{mission_id: mission_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
