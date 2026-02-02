defmodule Invader.Sprites do
  @moduledoc """
  Domain for managing sprite.dev environments.
  """
  use Ash.Domain,
    otp_app: :invader

  resources do
    resource Invader.Sprites.Sprite
  end

  @doc """
  Deletes a sprite and all related records (missions, waves).
  This handles foreign key constraints by deleting in the correct order.
  """
  def destroy_with_related(sprite) do
    import Ecto.Query

    # Delete waves for missions belonging to this sprite
    mission_ids =
      Invader.Repo.all(
        from m in "missions",
          where: m.sprite_id == ^sprite.id,
          select: m.id
      )

    if mission_ids != [] do
      Invader.Repo.delete_all(from w in "waves", where: w.mission_id in ^mission_ids)
    end

    # Delete missions for this sprite
    Invader.Repo.delete_all(from m in "missions", where: m.sprite_id == ^sprite.id)

    # Delete the sprite
    Ash.destroy!(sprite)
  end
end
