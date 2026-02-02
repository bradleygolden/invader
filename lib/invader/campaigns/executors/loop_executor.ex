defmodule Invader.Campaigns.Executors.LoopExecutor do
  @moduledoc """
  Executes loop-type workflow nodes.

  Manages iteration counting and evaluates continue conditions.
  """

  require Logger

  @doc """
  Execute a loop node.

  Config should contain:
  - max_iterations: Maximum number of iterations (default 10)
  - continue_condition: Expression to evaluate for continuing (optional)

  The context should contain an `iteration` key tracking current iteration.

  Returns {:ok, %{continue: true/false, iteration: n}} or {:error, reason}
  """
  def execute(config, context) do
    max_iterations = config["max_iterations"] || 10
    continue_condition = config["continue_condition"]

    # Get current iteration from context, default to 1
    current_iteration = Map.get(context, "loop_iteration", 1)

    # Check if we've exceeded max iterations
    if current_iteration > max_iterations do
      {:ok, %{continue: false, iteration: current_iteration, reason: :max_iterations_reached}}
    else
      # Evaluate continue condition if provided
      should_continue =
        if continue_condition && continue_condition != "" do
          case evaluate_condition(continue_condition, context) do
            {:ok, result} -> result
            {:error, _} -> false
          end
        else
          true
        end

      {:ok,
       %{
         continue: should_continue,
         iteration: current_iteration,
         next_iteration: current_iteration + 1
       }}
    end
  end

  defp evaluate_condition(condition, context) do
    bindings = [context: context]

    try do
      {result, _bindings} = Code.eval_string(condition, bindings)
      {:ok, !!result}
    rescue
      e ->
        Logger.warning("Loop condition evaluation failed: #{inspect(e)}")
        {:error, Exception.message(e)}
    end
  end
end
