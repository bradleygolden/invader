defmodule Invader.Prompts.Template do
  @moduledoc """
  Simple template engine for prompt variable substitution.

  Supports `{{variable}}` syntax for variable replacement.
  """

  @doc """
  Renders a template string with the given bindings.

  ## Examples

      iex> Template.render("Wave {{wave_number}} of {{max_waves}}", %{wave_number: 1, max_waves: 20})
      "Wave 1 of 20"

      iex> Template.render("Mission: {{mission_id}}", %{mission_id: "abc123"})
      "Mission: abc123"
  """
  def render(template, bindings) when is_binary(template) and is_map(bindings) do
    Regex.replace(~r/\{\{(\w+)\}\}/, template, fn _match, var_name ->
      key = String.to_atom(var_name)

      case Map.fetch(bindings, key) do
        {:ok, value} -> to_string(value)
        :error -> "{{#{var_name}}}"
      end
    end)
  end

  @doc """
  Builds standard bindings for a mission and wave.
  """
  def build_bindings(mission, wave_number) do
    sprite = Ash.load!(mission, :sprite).sprite

    %{
      wave_number: wave_number,
      max_waves: mission.max_waves,
      mission_id: mission.id,
      sprite_name: sprite.name,
      sprite_id: sprite.id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      current_wave: wave_number,
      remaining_waves: max(0, mission.max_waves - wave_number)
    }
  end
end
