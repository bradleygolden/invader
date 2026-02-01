defmodule Invader.Accounts.User.Changes.SetGitHubAttributes do
  @moduledoc """
  Sets user attributes from GitHub OAuth user_info and handles authorization.

  - First user to register becomes an admin
  - Subsequent users must already exist in the database (pre-authorized by admin)
  """
  use Ash.Resource.Change

  alias Invader.Accounts.User

  @impl true
  def change(changeset, _opts, _context) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info)
    github_id = user_info["id"]

    # Check if any users exist and if this GitHub user exists
    user_count = Ash.count!(User, authorize?: false)
    existing_user = User.get_by_github_id(github_id, authorize?: false, not_found_error?: false)

    cond do
      # First user ever - create as admin
      user_count == 0 ->
        set_github_attrs(changeset, user_info, is_admin: true)

      # Existing user - allow update
      existing_user != nil ->
        set_github_attrs(changeset, user_info)

      # Unknown user - reject
      true ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Changes.InvalidAttribute.exception(
            field: :github_login,
            message:
              "User '#{user_info["login"]}' is not authorized. Please ask an admin to add you."
          )
        )
    end
  end

  defp set_github_attrs(changeset, user_info, opts \\ []) do
    attrs = %{
      github_id: user_info["id"],
      github_login: user_info["login"],
      email: user_info["email"],
      name: user_info["name"],
      avatar_url: user_info["avatar_url"]
    }

    attrs =
      if Keyword.get(opts, :is_admin, false) do
        Map.put(attrs, :is_admin, true)
      else
        attrs
      end

    Ash.Changeset.change_attributes(changeset, attrs)
  end
end
