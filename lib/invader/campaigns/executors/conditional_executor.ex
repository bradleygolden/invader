defmodule Invader.Campaigns.Executors.ConditionalExecutor do
  @moduledoc """
  Executes conditional-type workflow nodes.

  Evaluates a condition expression and returns which branch to take.
  """

  require Logger

  @doc """
  Execute a conditional node.

  Config should contain:
  - condition: An Elixir expression string that evaluates to true/false

  The expression can reference `context` to access workflow variables.

  Returns {:ok, %{branch: "true" | "false"}} or {:error, reason}
  """
  def execute(config, context) do
    condition = config["condition"] || "true"

    case evaluate_condition(condition, context) do
      {:ok, true} ->
        {:ok, %{branch: "true", condition_result: true}}

      {:ok, false} ->
        {:ok, %{branch: "false", condition_result: false}}

      {:error, error} ->
        {:error, {:condition_evaluation_failed, error}}
    end
  end

  defp evaluate_condition(condition, context) do
    # Create a binding with the context available
    bindings = [context: context]

    try do
      {result, _bindings} = Code.eval_string(condition, bindings)
      {:ok, !!result}
    rescue
      e ->
        Logger.warning("Conditional evaluation failed: #{inspect(e)}")
        {:error, Exception.message(e)}
    end
  end
end
