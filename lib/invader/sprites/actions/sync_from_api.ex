defmodule Invader.Sprites.Actions.SyncFromApi do
  @moduledoc """
  Syncs sprites from the Sprites API into the database.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(_input, _opts, _context) do
    token = System.get_env("SPRITES_TOKEN") || raise "SPRITES_TOKEN not set"
    client = Sprites.new(token)

    case Sprites.list(client) do
      {:ok, sprites_data} ->
        sprites = sync_sprites(sprites_data)
        {:ok, sprites}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_sprites(sprites_data) do
    # Get all local sprite names before syncing
    local_sprites = Invader.Sprites.Sprite.list!()
    local_names = MapSet.new(local_sprites, & &1.name)

    # Sync sprites from API and track synced names
    {synced_sprites, synced_names} =
      Enum.map_reduce(sprites_data, MapSet.new(), fn sprite_data, acc ->
        name = sprite_data["name"] || sprite_data[:name]
        org = sprite_data["organization"] || sprite_data[:organization]
        status = parse_status(sprite_data["status"] || sprite_data[:status])

        sprite =
          case Invader.Sprites.Sprite.get_by_name(name) do
            {:ok, existing} ->
              existing
              |> Ash.Changeset.for_update(:update, %{org: org, status: status})
              |> Ash.update!()

            {:error, _} ->
              Invader.Sprites.Sprite.create!(%{name: name, org: org, status: status})
          end

        {sprite, MapSet.put(acc, name)}
      end)

    # Delete local sprites that no longer exist in the API
    names_to_delete = MapSet.difference(local_names, synced_names)

    for sprite <- local_sprites, sprite.name in names_to_delete do
      Ash.destroy!(sprite)
    end

    synced_sprites
  end

  defp parse_status("running"), do: :available
  defp parse_status("warm"), do: :available
  defp parse_status("stopped"), do: :offline
  defp parse_status("cold"), do: :offline
  defp parse_status("busy"), do: :busy
  defp parse_status(status) when is_atom(status), do: status
  defp parse_status(_), do: :unknown
end
