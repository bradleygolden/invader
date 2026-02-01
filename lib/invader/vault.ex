defmodule Invader.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive data at rest using AES-256-GCM.

  Requires the CLOAK_KEY environment variable to be set with a Base64-encoded
  256-bit key. Generate one with: `openssl rand -base64 32`
  """
  use Cloak.Vault, otp_app: :invader

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: get_key!(config), iv_length: 12
        }
      )

    {:ok, config}
  end

  defp get_key!(config) do
    case Keyword.get(config, :key) do
      nil -> decode_env!("CLOAK_KEY")
      key when is_binary(key) -> key
    end
  end

  defp decode_env!(var) do
    case System.get_env(var) do
      nil -> raise "Missing required environment variable: #{var}"
      val -> Base.decode64!(val)
    end
  end
end
