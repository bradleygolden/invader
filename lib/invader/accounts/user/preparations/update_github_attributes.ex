defmodule Invader.Accounts.User.Preparations.UpdateGitHubAttributes do
  @moduledoc """
  Preparation for GitHub OAuth sign-in that updates user attributes after successful sign-in.

  This runs after the user is found and updates their github_id, email, name, and avatar_url
  with the latest data from GitHub. This is especially important for first-time sign-ins
  where the user was pre-authorized by github_login but doesn't have a github_id yet.
  """
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.after_action(query, fn _query, results ->
      user_info = Ash.Query.get_argument(query, :user_info)

      # Update each user with the GitHub attributes
      # Note: user_info uses OpenID Connect fields:
      #   "sub" -> github_id, "preferred_username" -> github_login, "picture" -> avatar_url
      updated_results =
        Enum.map(results, fn user ->
          attrs = %{
            github_id: user_info["sub"],
            github_login: user_info["preferred_username"],
            email: user_info["email"] || user.email,
            name: user_info["name"] || user.name,
            avatar_url: user_info["picture"]
          }

          case Ash.update(user, attrs, action: :update_from_oauth, authorize?: false) do
            {:ok, updated_user} -> updated_user
            {:error, _} -> user
          end
        end)

      {:ok, updated_results}
    end)
  end
end
