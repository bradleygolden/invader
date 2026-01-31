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
    Enum.map(sprites_data, fn sprite_data ->
      name = sprite_data["name"] || sprite_data[:name]
      status = parse_status(sprite_data["status"] || sprite_data[:status])

      case Invader.Sprites.Sprite.get_by_name(name) do
        {:ok, existing} ->
          Invader.Sprites.Sprite.update_status!(existing, status)

        {:error, _} ->
          Invader.Sprites.Sprite.create!(%{name: name, status: status})
      end
    end)
  end

  defp parse_status("running"), do: :available
  defp parse_status("stopped"), do: :offline
  defp parse_status("busy"), do: :busy
  defp parse_status(status) when is_atom(status), do: status
  defp parse_status(_), do: :unknown
end
