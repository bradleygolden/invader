defmodule Invader.Campaigns.Executors.DelayExecutor do
  @moduledoc """
  Executes delay-type workflow nodes.

  Pauses execution for a specified duration.
  """

  @doc """
  Execute a delay node.

  Config should contain:
  - delay_seconds: Number of seconds to wait

  Returns {:ok, %{delayed_seconds: n}} or {:error, reason}
  """
  def execute(config, _context) do
    delay_seconds = config["delay_seconds"] || 60

    if is_integer(delay_seconds) and delay_seconds > 0 do
      # Sleep for the specified duration
      Process.sleep(delay_seconds * 1000)
      {:ok, %{delayed_seconds: delay_seconds}}
    else
      {:error, :invalid_delay_seconds}
    end
  end
end
