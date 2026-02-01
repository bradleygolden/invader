defmodule Invader.Factory do
  @moduledoc """
  Test factory for creating test resources.

  Provides build/insert helpers for sprites, connections, missions, and scope presets.
  """

  alias Invader.Connections.Connection
  alias Invader.Missions.Mission
  alias Invader.Scopes.ScopePreset
  alias Invader.Sprites.Sprite

  @doc """
  Build a resource with the given attributes (does not persist).
  """
  def build(type, attrs \\ %{})

  def build(:sprite, attrs) do
    defaults = %{
      name: "test-sprite-#{unique_id()}",
      org: "test-org",
      status: :available
    }

    Map.merge(defaults, attrs)
  end

  def build(:connection, attrs) do
    defaults = %{
      type: :github,
      name: "Test GitHub Connection",
      app_id: "123456",
      installation_id: "789012",
      private_key: generate_test_private_key()
    }

    Map.merge(defaults, attrs)
  end

  def build(:scope_preset, attrs) do
    defaults = %{
      name: "test-preset-#{unique_id()}",
      description: "Test scope preset",
      scopes: ["github:pr:list", "github:issue:view"],
      is_system: false
    }

    Map.merge(defaults, attrs)
  end

  def build(:mission, attrs) do
    defaults = %{
      prompt: "Test mission prompt",
      max_waves: 10,
      priority: 0
    }

    Map.merge(defaults, attrs)
  end

  @doc """
  Insert a resource into the database.
  """
  def insert!(type, attrs \\ %{})

  def insert!(:sprite, attrs) do
    attrs = build(:sprite, attrs)

    {:ok, sprite} = Sprite.create(attrs)
    sprite
  end

  def insert!(:connection, attrs) do
    attrs = build(:connection, attrs)

    {:ok, connection} = Connection.create(attrs)
    connection
  end

  def insert!(:scope_preset, attrs) do
    attrs = build(:scope_preset, attrs)

    {:ok, preset} = ScopePreset.create(attrs)
    preset
  end

  def insert!(:mission, attrs) do
    # Ensure sprite_id is present
    attrs =
      if Map.has_key?(attrs, :sprite_id) do
        attrs
      else
        sprite = insert!(:sprite)
        Map.put(attrs, :sprite_id, sprite.id)
      end

    attrs = build(:mission, attrs)

    {:ok, mission} = Mission.create(attrs)
    mission
  end

  @doc """
  Generate a valid Phoenix token for testing.
  """
  def generate_token(claims) do
    Phoenix.Token.sign(InvaderWeb.Endpoint, "sprite_proxy", claims)
  end

  defp unique_id do
    :erlang.unique_integer([:positive])
  end

  defp generate_test_private_key do
    # A minimal RSA private key for testing
    # This is intentionally a test-only key and not used for real authentication
    """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEowIBAAKCAQEA0Z3VS5JJcds3xfn/ygWyF8PbnGy0AHB7MaeV2EbvLvMhLtDG
    xSPhzjYjH4Wm7bFxpC1LpJdFGdpp1YNytXYI7/GioLvNcXjKQpYHsq3TotkxPGcx
    X3OBUXJfIHk+Be8lRHjEXKzf1bKE7TbZxRIJ8oYu3VAxkRvkfJ+zVxJfS6fIAfHD
    xmxrR6kHVrcPBzr7r+J5/M8SXJlpSsLo/hNsLMVvVxdyTFpv5VEQlK2FirVdl2+s
    9RHB2RzQrF7kXbfL7gKN0djlIrv8VL3IJuIzTpHSDMfLXmrz9r6YGGP+g0pDlLqi
    J/2g11e0C1W9FJBYpvH4dGbL5MxWy2JzVMh1fQIDAQABAoIBAFy3T5gnXuuNLnpE
    rErLBJqCz9ULyPz9qGOC3DwPANnUbuRvpz8RBETIkGXlPBQvxGJmrxJ/mFQtEbIk
    vJRPCNGHNADZFdXHGgxz/IZmC6QfLLnElQqPe8PuLvJxC1H4vxPBBqLxTbYlk/Xf
    EvVnMEJ7h9qWYDCqGPXNvA8wF6BL+yAz9F5c6wvCJqAf7cFBJc+J7C8XVnqCJW/N
    2rZKY5WsNQm8dBNsEU8ksNl09fKHqWwMRJKEE7RhLxCT7j7jFm9ROXzf5V5x5xQf
    w7KNpuxNCo2cYlJ0SzE67WB2Qm6r8G9l+BJ+NNMljL0xSEMqV+9LK5iFPvQdX6x7
    8e08QwECgYEA7D1q6G8QEnE2N4+4hwz8DvIVPMcHZ6T0C3B8WPnrR/9VKfQd2DLz
    k0GjLqNdpq6dqpcX1T/0yLxA9z4n3Jdm3fqGIJGUxlk2Ke6L6YjlF/Yv/mLlvZl0
    5qMQm6G4L7h8Rr0xEqRVbEo+GSqJ7nL9RvXZx8LnKEQkR8D+Z0fZfQECgYEA42PV
    vCI7oSFBNhqqpXXzYyIo9p0t0F0PGXJdTzFfMxZoSeAM0VZBPf3dGGLi0IjQIRFm
    J3cZXe7G8HvGjbYmR78WMoV3qCbKGUlJmjLM0Lq7Mi+PvkcjEQPQg0RZnX3J7qbP
    XZTLdCBvXxZMSD0wB5Ro0DAoQ0H0QVR7J5nph/0CgYBbKT7C5sNpcK0L2Rfq0Mog
    xpXYq3vNxJpR8TZfWk/tCvBz3gvzL7H2H0MNh+4vR7g2mJ9PyW7K6m0M7fGl0JAe
    j0R0lL/F0gXyFvLfzNBdLm1/xP+/lQs9WAaJKgEL9b9zRqfYdKN1PZWlPxNP/lLc
    pdJS8g6lS3DNXAU9fwN4AQKBgCq9LDVzWF0rI8sqwG8nKqG8JdNyiYgO0zJxoZ2H
    vP2Vy+9RfQHd4QdcHPnFxGK3mfn/g0JZpNuWlV3jUB8wF5tIW9v4oK3e4U5u9xN2
    n6cDYLrH3P7jFBYvM3HW1XJMXqcJIyJnWIHlBaoy4S1z7cM0P5j3b4q7J7N1Wbop
    j3oFAoGBAMwzJy4uM0pEZCmJ+f59k6n9B6xvPxJYL+h3AaKKJ5n8R8QJQZ7MljPF
    k7/+OD9Wl4L5lWsZ9eC9/YJPsJVBqXh0p4Y+q8XKBOT9ZV7VZ/+o9iL7pG9mYqfT
    jJmDjZV7UBouEVZ2REhNmLk/bS8RBYV0dq3Y4Wh7LpNjF8vZmZxJ
    -----END RSA PRIVATE KEY-----
    """
  end
end
