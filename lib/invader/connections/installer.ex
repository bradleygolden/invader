defmodule Invader.Connections.Installer do
  @moduledoc """
  Installs the Invader CLI on sprites via SpriteCli.

  The CLI provides a proxy interface for GitHub commands, allowing
  sprites to execute GitHub operations through Invader without
  needing their own GitHub tokens.
  """

  alias Invader.SpriteCli.Cli

  @doc """
  Installs the Invader CLI on a sprite.

  ## Parameters

    - sprite_name: Name of the sprite to install on
    - invader_url: URL of the Invader instance (e.g., "https://invader.fly.dev")
    - token: Authentication token for the sprite to use when calling Invader

  ## Returns

    - {:ok, output} on success
    - {:error, reason} on failure
  """
  def install_cli(sprite_name, invader_url, token) do
    command = """
    curl -fsSL #{invader_url}/cli/install.sh | bash -s -- #{invader_url} #{token}
    """

    case Cli.exec(sprite_name, command) do
      {:ok, output} ->
        {:ok, output}

      {:error, {exit_code, output}} ->
        {:error, "Installation failed (exit code #{exit_code}): #{output}"}

      {:error, reason} ->
        {:error, "Installation failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Uninstalls the Invader CLI from a sprite.

  ## Parameters

    - sprite_name: Name of the sprite to uninstall from

  ## Returns

    - {:ok, output} on success
    - {:error, reason} on failure
  """
  def uninstall_cli(sprite_name) do
    command = "rm -f /usr/local/bin/invader ~/.config/invader/config"

    case Cli.exec(sprite_name, command) do
      {:ok, output} ->
        {:ok, output}

      {:error, {exit_code, output}} ->
        {:error, "Uninstallation failed (exit code #{exit_code}): #{output}"}

      {:error, reason} ->
        {:error, "Uninstallation failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Checks if the Invader CLI is installed on a sprite.

  ## Returns

    - {:ok, :installed} if installed
    - {:ok, :not_installed} if not installed
    - {:error, reason} on failure
  """
  def check_installed(sprite_name) do
    case Cli.exec(sprite_name, "which invader") do
      {:ok, output} when output != "" ->
        {:ok, :installed}

      {:ok, _} ->
        {:ok, :not_installed}

      {:error, {1, _}} ->
        # Exit code 1 means "which" found nothing
        {:ok, :not_installed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Tests the Invader CLI on a sprite by running a simple command.

  ## Returns

    - {:ok, :working} if the CLI is functioning
    - {:error, reason} on failure
  """
  def test_cli(sprite_name) do
    case Cli.exec(sprite_name, "invader --help") do
      {:ok, output} ->
        if String.contains?(output, "invader") || String.contains?(output, "Usage") do
          {:ok, :working}
        else
          {:error, "Unexpected output: #{output}"}
        end

      {:error, {exit_code, output}} ->
        {:error, "CLI test failed (exit code #{exit_code}): #{output}"}

      {:error, reason} ->
        {:error, "CLI test failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates a unique token for a sprite.

  This token is used to authenticate the sprite when calling Invader's proxy API.
  Currently generates a random token - in production you may want to use
  Phoenix.Token or similar for signed tokens.
  """
  def generate_sprite_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
