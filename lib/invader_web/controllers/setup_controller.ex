defmodule InvaderWeb.SetupController do
  @moduledoc """
  Handles admin setup and user creation.
  """
  use InvaderWeb, :controller

  alias Invader.Accounts.User

  @doc """
  Legacy token validation - redirects to sign-in with validated session.
  """
  def validate(conn, %{"token" => token}) do
    expected_token = Application.get_env(:invader, :admin_setup_token)

    if expected_token && token == expected_token do
      conn
      |> put_session(:admin_setup_validated, true)
      |> redirect(to: ~p"/sign-in")
    else
      conn
      |> put_flash(:error, "Invalid setup token")
      |> redirect(to: ~p"/sign-in")
    end
  end

  @doc """
  Creates the initial admin user after validating the setup token.
  Accepts auth_method of "github" or "magic_link" with corresponding identifier.
  """
  def create_admin(conn, %{"token" => token, "auth_method" => method, "identifier" => identifier}) do
    expected_token = Application.get_env(:invader, :admin_setup_token)

    cond do
      is_nil(expected_token) or expected_token == "" ->
        conn
        |> put_flash(:error, "Setup token not configured")
        |> redirect(to: ~p"/sign-in")

      token != expected_token ->
        conn
        |> put_flash(:error, "Invalid setup token")
        |> redirect(to: ~p"/sign-in")

      String.trim(identifier) == "" ->
        conn
        |> put_flash(:error, "Identifier is required")
        |> redirect(to: ~p"/sign-in")

      true ->
        create_admin_user(conn, method, String.trim(identifier))
    end
  end

  def create_admin(conn, _params) do
    conn
    |> put_flash(:error, "Missing required fields")
    |> redirect(to: ~p"/sign-in")
  end

  defp create_admin_user(conn, "github", github_login) do
    attrs = %{github_login: github_login, is_admin: true}

    case Ash.create(User, attrs, action: :create, authorize?: false) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Admin account created. Sign in with GitHub to activate.")
        |> redirect(to: ~p"/sign-in")

      {:error, error} ->
        conn
        |> put_flash(:error, "Failed to create admin: #{inspect_error(error)}")
        |> redirect(to: ~p"/sign-in")
    end
  end

  defp create_admin_user(conn, "magic_link", email) do
    if valid_email?(email) do
      attrs = %{email: email, is_admin: true}

      case Ash.create(User, attrs, action: :create, authorize?: false) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Admin account created. Request a magic link to sign in.")
          |> redirect(to: ~p"/sign-in")

        {:error, error} ->
          conn
          |> put_flash(:error, "Failed to create admin: #{inspect_error(error)}")
          |> redirect(to: ~p"/sign-in")
      end
    else
      conn
      |> put_flash(:error, "Invalid email address")
      |> redirect(to: ~p"/sign-in")
    end
  end

  defp create_admin_user(conn, _method, _identifier) do
    conn
    |> put_flash(:error, "Invalid authentication method")
    |> redirect(to: ~p"/sign-in")
  end

  defp valid_email?(email) do
    String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end

  defp inspect_error(%Ash.Error.Invalid{} = error) do
    error.errors
    |> Enum.map(fn e -> Map.get(e, :message, "Unknown error") end)
    |> Enum.join(", ")
  end

  defp inspect_error(_error), do: "Unknown error"
end
