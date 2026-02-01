defmodule Invader.Scopes.Checker do
  @moduledoc """
  Checks if a given scope is allowed by a mission's scope configuration.

  Scope Format:
    integration:category:action

  Examples:
    - "github:*"           → All GitHub access
    - "github:pr:*"        → All PR commands
    - "github:pr:list"     → Specific command
    - "github:issue:view"  → View issues only
    - "*"                  → Full access to everything

  Wildcards:
    - "*" matches any segment
    - A scope "github:*" matches "github:pr:list", "github:issue:view", etc.
    - A scope "github:pr:*" matches "github:pr:list", "github:pr:view", etc.
  """

  alias Invader.Scopes.ScopePreset

  @doc """
  Checks if a scope string is allowed by the mission's configuration.

  Returns `true` if the scope is allowed, `false` otherwise.

  ## Examples

      iex> mission = %{scopes: ["github:pr:*", "github:issue:view"]}
      iex> Checker.allowed?(mission, "github:pr:list")
      true
      iex> Checker.allowed?(mission, "github:issue:create")
      false
  """
  def allowed?(mission, scope_string) when is_binary(scope_string) do
    effective_scopes = get_effective_scopes(mission)

    # If no scopes configured, allow all (backward compatibility)
    if effective_scopes == [] or effective_scopes == nil do
      true
    else
      Enum.any?(effective_scopes, fn allowed_scope ->
        scope_matches?(allowed_scope, scope_string)
      end)
    end
  end

  @doc """
  Gets the effective scopes for a mission by merging preset and inline scopes.

  Inline scopes take precedence. If both are nil/empty, returns empty list.
  """
  def get_effective_scopes(mission) do
    inline_scopes = get_inline_scopes(mission)
    preset_scopes = get_preset_scopes(mission)

    cond do
      # Inline scopes override preset
      inline_scopes != nil and inline_scopes != [] ->
        inline_scopes

      # Fall back to preset
      preset_scopes != nil and preset_scopes != [] ->
        preset_scopes

      # No scopes configured
      true ->
        []
    end
  end

  @doc """
  Checks if a specific scope pattern matches a requested scope.

  ## Examples

      iex> Checker.scope_matches?("*", "github:pr:list")
      true
      iex> Checker.scope_matches?("github:*", "github:pr:list")
      true
      iex> Checker.scope_matches?("github:pr:*", "github:pr:list")
      true
      iex> Checker.scope_matches?("github:pr:list", "github:pr:list")
      true
      iex> Checker.scope_matches?("github:pr:list", "github:pr:view")
      false
  """
  def scope_matches?(allowed_scope, requested_scope) do
    # Full wildcard matches everything
    if allowed_scope == "*" do
      true
    else
      allowed_parts = String.split(allowed_scope, ":")
      requested_parts = String.split(requested_scope, ":")

      match_parts(allowed_parts, requested_parts)
    end
  end

  # Match scope parts with wildcard support
  defp match_parts([], []), do: true
  defp match_parts(["*" | _], _requested), do: true

  defp match_parts([part | rest_allowed], [part | rest_requested]) do
    match_parts(rest_allowed, rest_requested)
  end

  defp match_parts(_, _), do: false

  defp get_inline_scopes(%{scopes: scopes}) when is_list(scopes), do: scopes
  defp get_inline_scopes(_), do: nil

  defp get_preset_scopes(%{scope_preset: %ScopePreset{scopes: scopes}}) when is_list(scopes) do
    scopes
  end

  defp get_preset_scopes(%{scope_preset_id: preset_id}) when is_binary(preset_id) do
    case ScopePreset.get(preset_id) do
      {:ok, preset} -> preset.scopes
      _ -> nil
    end
  end

  defp get_preset_scopes(_), do: nil
end
