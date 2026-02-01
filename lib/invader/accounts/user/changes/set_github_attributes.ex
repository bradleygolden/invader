defmodule Invader.Accounts.User.Changes.SetGitHubAttributes do
  @moduledoc """
  Sets user attributes from GitHub OAuth user_info and handles authorization.

  Users must be pre-authorized in the database (created via admin setup or by an admin).
  This change matches incoming GitHub users by github_id (returning users) or
  github_login (first-time sign-in for pre-authorized users).
  """
  use Ash.Resource.Change

  alias Invader.Accounts.User

  @impl true
  def change(changeset, _opts, context) do
    # Skip if this is already an update action (sign_in_with_github)
    if changeset.action.type == :update do
      set_github_attrs(changeset)
    else
      handle_create(changeset, context)
    end
  end

  defp handle_create(changeset, _context) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info)
    oauth_tokens = Ash.Changeset.get_argument(changeset, :oauth_tokens)
    github_id = user_info["id"]
    github_login = user_info["login"]

    # Check if this GitHub user exists by ID (returning user)
    existing_by_id =
      case User.get_by_github_id(github_id, authorize?: false, not_found_error?: false) do
        {:ok, user} -> user
        _ -> nil
      end

    # Check if pre-authorized by github_login (first-time sign-in)
    pre_authorized =
      case User.get_by_github_login(github_login, authorize?: false, not_found_error?: false) do
        {:ok, user} -> user
        _ -> nil
      end

    cond do
      # Existing user by github_id - the upsert will handle this
      existing_by_id != nil ->
        set_github_attrs(changeset)

      # Pre-authorized by github_login but no github_id - update them directly
      pre_authorized != nil && pre_authorized.github_id == nil ->
        # Update the pre-authorized user with GitHub data
        case Ash.update(pre_authorized, %{user_info: user_info, oauth_tokens: oauth_tokens},
               action: :sign_in_with_github,
               authorize?: false
             ) do
          {:ok, updated_user} ->
            # Return the updated user by setting it on the changeset
            # and marking the changeset as already handled
            changeset
            |> Ash.Changeset.force_change_attribute(:id, updated_user.id)
            |> Ash.Changeset.force_change_attribute(:github_id, updated_user.github_id)
            |> Ash.Changeset.force_change_attribute(:github_login, updated_user.github_login)
            |> Ash.Changeset.force_change_attribute(:email, updated_user.email)
            |> Ash.Changeset.force_change_attribute(:name, updated_user.name)
            |> Ash.Changeset.force_change_attribute(:avatar_url, updated_user.avatar_url)
            |> Ash.Changeset.force_change_attribute(:is_admin, updated_user.is_admin)

          {:error, error} ->
            Ash.Changeset.add_error(changeset, error)
        end

      # Unknown user - reject
      true ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Changes.InvalidAttribute.exception(
            field: :github_login,
            message: "User '#{github_login}' is not authorized. Please ask an admin to add you."
          )
        )
    end
  end

  defp set_github_attrs(changeset) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info)

    attrs = %{
      github_id: user_info["id"],
      github_login: user_info["login"],
      email: user_info["email"],
      name: user_info["name"],
      avatar_url: user_info["avatar_url"]
    }

    Ash.Changeset.change_attributes(changeset, attrs)
  end
end
