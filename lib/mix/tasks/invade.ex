defmodule Mix.Tasks.Invade do
  @moduledoc """
  Mix task wrapper for the Invader CLI.

  Usage:
    mix invade start PROMPT.md --sprite NAME --waves N
    mix invade queue list
    mix invade status
    mix invade help
  """
  use Mix.Task

  @shortdoc "Run Invader CLI commands"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Invader.CLI.main(args)
  end
end
