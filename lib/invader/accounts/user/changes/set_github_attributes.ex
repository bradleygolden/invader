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
  def change(changeset, _opts, _context) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info)
    github_id = user_info["id"]
    github_login = user_info["login"]

    # Check if this GitHub user exists by ID (returning user)
    existing_by_id = User.get_by_github_id(github_id, authorize?: false, not_found_error?: false)

    # Check if pre-authorized by github_login (first-time sign-in)
    pre_authorized =
      User.get_by_github_login(github_login, authorize?: false, not_found_error?: false)

    cond do
      # Existing user by github_id - allow update
      existing_by_id != nil ->
        set_github_attrs(changeset, user_info)

      # Pre-authorized by github_login - first-time sign-in
      pre_authorized != nil ->
        set_github_attrs(changeset, user_info)

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

  defp set_github_attrs(changeset, user_info) do
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
