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
    require Logger
    user_info = Ash.Query.get_argument(query, :user_info)
    Logger.info("OAuth user_info: #{inspect(user_info)}")

    Ash.Query.after_action(query, fn _query, results ->
      user_info = Ash.Query.get_argument(query, :user_info)

      # Update each user with the GitHub attributes
      updated_results =
        Enum.map(results, fn user ->
          attrs = %{
            github_id: user_info["id"],
            github_login: user_info["login"],
            email: user_info["email"] || user.email,
            name: user_info["name"] || user.name,
            avatar_url: user_info["avatar_url"]
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
