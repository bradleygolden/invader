defmodule Invader.CLI do
  @moduledoc """
  Command-line interface for Invader - Agent Orchestrator.

  Usage:
    invade start [PROMPT.md] --sprite NAME --waves N --duration TIME
    invade queue add PROMPT.md --priority N
    invade queue list
    invade status
    invade waves
    invade logs
    invade save [--comment TEXT]
    invade saves
    invade load CHECKPOINT_ID
    invade pause
    invade resume
    invade abort
    invade dashboard
  """

  alias Invader.Missions
  alias Invader.Sprites
  alias Invader.Saves
  alias Invader.SpriteCli.Cli

  def main(args) do
    args
    |> parse_args()
    |> run()
  end

  defp parse_args(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          sprite: :string,
          waves: :integer,
          duration: :integer,
          priority: :integer,
          comment: :string,
          help: :boolean
        ],
        aliases: [
          s: :sprite,
          w: :waves,
          d: :duration,
          p: :priority,
          c: :comment,
          h: :help
        ]
      )

    {args, opts}
  end

  defp run({["help"], _opts}), do: help()
  defp run({[], [help: true]}), do: help()
  defp run({[], _opts}), do: status()

  # Start a mission
  defp run({["start" | rest], opts}) do
    prompt_path =
      case rest do
        [path] -> Path.expand(path)
        [] -> Path.expand("PROMPT.md")
      end

    sprite_name = opts[:sprite] || raise "Missing --sprite option"
    max_waves = opts[:waves] || 20
    max_duration = opts[:duration]

    with {:ok, sprite} <- get_or_create_sprite(sprite_name),
         {:ok, mission} <-
           Missions.Mission.create(%{
             prompt_path: prompt_path,
             sprite_id: sprite.id,
             max_waves: max_waves,
             max_duration: max_duration
           }),
         {:ok, mission} <- Missions.Mission.start(mission) do
      Invader.Workers.LoopRunner.enqueue(mission.id)
      puts_green("▶ Mission started: #{mission.id}")
      puts_dim("  Sprite: #{sprite_name}")
      puts_dim("  Prompt: #{prompt_path}")
      puts_dim("  Max waves: #{max_waves}")
    else
      {:error, reason} ->
        puts_red("✗ Failed to start mission: #{inspect(reason)}")
    end
  end

  # Queue commands
  defp run({["queue", "add", prompt_path], opts}) do
    prompt_path = Path.expand(prompt_path)
    sprite_name = opts[:sprite] || raise "Missing --sprite option"
    priority = opts[:priority] || 0

    with {:ok, sprite} <- get_or_create_sprite(sprite_name),
         {:ok, mission} <-
           Missions.Mission.create(%{
             prompt_path: prompt_path,
             sprite_id: sprite.id,
             priority: priority,
             max_waves: opts[:waves] || 20
           }) do
      puts_green("+ Added to queue: #{mission.id}")
      puts_dim("  Priority: #{priority}")
    else
      {:error, reason} ->
        puts_red("✗ Failed to add to queue: #{inspect(reason)}")
    end
  end

  defp run({["queue", "list"], _opts}) do
    missions =
      Missions.Mission.list!()
      |> Ash.load!([:sprite])
      |> Enum.filter(&(&1.status == :pending))
      |> Enum.sort_by(& &1.priority, :desc)

    if Enum.empty?(missions) do
      puts_dim("Queue is empty")
    else
      puts_green("📋 Mission Queue")

      Enum.each(Enum.with_index(missions), fn {m, i} ->
        IO.puts(
          "  #{i + 1}. #{m.sprite.name} - #{Path.basename(m.prompt_path)} (priority: #{m.priority})"
        )
      end)
    end
  end

  defp run({["queue"], _opts}), do: run({["queue", "list"], []})

  # Status
  defp run({["status"], _opts}) do
    status()
  end

  # Waves (show recent waves)
  defp run({["waves"], _opts}) do
    waves =
      Invader.Missions.Wave.list!()
      |> Ash.load!([:mission])
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(20)

    if Enum.empty?(waves) do
      puts_dim("No waves recorded")
    else
      puts_green("🌊 Recent Waves")

      Enum.each(waves, fn w ->
        status_icon = if w.exit_code == 0, do: "✓", else: "✗"
        mission = w.mission

        IO.puts(
          "  #{status_icon} Wave #{w.number} - Mission #{String.slice(mission.id, 0, 8)}..."
        )
      end)
    end
  end

  # Logs (show recent output)
  defp run({["logs"], _opts}) do
    waves =
      Invader.Missions.Wave.list!()
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(5)

    if Enum.empty?(waves) do
      puts_dim("No logs available")
    else
      Enum.each(waves, fn w ->
        puts_green("=== Wave #{w.number} ===")
        IO.puts(w.output || "(no output)")
        IO.puts("")
      end)
    end
  end

  # Save commands
  defp run({["save"], opts}) do
    comment = opts[:comment]
    sprite_name = opts[:sprite]

    unless sprite_name do
      puts_red("✗ Missing --sprite option")
      System.halt(1)
    end

    case Cli.checkpoint_create(sprite_name, comment) do
      {:ok, checkpoint_id} ->
        puts_green("💾 Checkpoint created: #{checkpoint_id}")

      {:error, reason} ->
        puts_red("✗ Failed to create checkpoint: #{inspect(reason)}")
    end
  end

  defp run({["saves"], opts}) do
    sprite_name = opts[:sprite]

    saves =
      if sprite_name do
        {:ok, sprite} = Sprites.Sprite.get_by_name(sprite_name)
        Saves.Save.for_sprite!(sprite.id)
      else
        Saves.Save.list!()
      end
      |> Ash.load!([:sprite])
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(20)

    if Enum.empty?(saves) do
      puts_dim("No saves found")
    else
      puts_green("💾 Saves")

      Enum.each(saves, fn s ->
        comment = s.comment || "wave-#{s.wave_number}"
        IO.puts("  #{s.checkpoint_id} - #{s.sprite.name} - #{comment}")
      end)
    end
  end

  defp run({["load", checkpoint_id], opts}) do
    sprite_name = opts[:sprite]

    unless sprite_name do
      puts_red("✗ Missing --sprite option")
      System.halt(1)
    end

    case Cli.restore(sprite_name, checkpoint_id) do
      {:ok, _} ->
        puts_green("↺ Restored checkpoint: #{checkpoint_id}")

      {:error, reason} ->
        puts_red("✗ Failed to restore: #{inspect(reason)}")
    end
  end

  # Mission control
  defp run({["pause"], opts}) do
    with {:ok, mission} <- get_active_mission(opts) do
      {:ok, _} = Missions.Mission.pause(mission)
      puts_green("⏸ Mission paused")
    end
  end

  defp run({["resume"], opts}) do
    with {:ok, mission} <- get_paused_mission(opts) do
      {:ok, mission} = Missions.Mission.resume(mission)
      Invader.Workers.LoopRunner.enqueue(mission.id)
      puts_green("▶ Mission resumed")
    end
  end

  defp run({["abort"], opts}) do
    with {:ok, mission} <- get_active_or_paused_mission(opts) do
      {:ok, _} = Missions.Mission.abort(mission)
      puts_green("✕ Mission aborted")
    end
  end

  # Dashboard
  defp run({["dashboard"], _opts}) do
    port = Application.get_env(:invader, InvaderWeb.Endpoint)[:http][:port] || 4000
    url = "http://localhost:#{port}"

    IO.puts("Opening dashboard at #{url}")
    System.cmd("open", [url])
  end

  defp run({[cmd | _], _opts}) do
    puts_red("Unknown command: #{cmd}")
    help()
  end

  # Helpers

  defp status do
    missions = Missions.Mission.list!() |> Ash.load!([:sprite, :waves])
    running = Enum.filter(missions, &(&1.status == :running))
    pending = Enum.filter(missions, &(&1.status == :pending))

    puts_green("◄ INVADER STATUS ►")
    IO.puts("")

    if Enum.empty?(running) do
      puts_dim("  No active missions")
    else
      puts_green("  Active Missions:")

      Enum.each(running, fn m ->
        IO.puts("    ▶ #{m.sprite.name} - Wave #{m.current_wave}/#{m.max_waves}")
      end)
    end

    IO.puts("")
    IO.puts("  Queue: #{length(pending)} pending")
    IO.puts("  Total: #{length(missions)} missions")
  end

  defp get_or_create_sprite(name) do
    case Sprites.Sprite.get_by_name(name) do
      {:ok, sprite} ->
        {:ok, sprite}

      {:error, %Ash.Error.Query.NotFound{}} ->
        Sprites.Sprite.create(%{name: name, status: :available})
    end
  end

  defp get_active_mission(opts) do
    sprite_name = opts[:sprite]

    missions =
      Missions.Mission.list!()
      |> Ash.load!([:sprite])
      |> Enum.filter(&(&1.status == :running))

    missions =
      if sprite_name do
        Enum.filter(missions, &(&1.sprite.name == sprite_name))
      else
        missions
      end

    case missions do
      [mission | _] -> {:ok, mission}
      [] -> {:error, "No active mission found"}
    end
  end

  defp get_paused_mission(opts) do
    sprite_name = opts[:sprite]

    missions =
      Missions.Mission.list!()
      |> Ash.load!([:sprite])
      |> Enum.filter(&(&1.status == :paused))

    missions =
      if sprite_name do
        Enum.filter(missions, &(&1.sprite.name == sprite_name))
      else
        missions
      end

    case missions do
      [mission | _] -> {:ok, mission}
      [] -> {:error, "No paused mission found"}
    end
  end

  defp get_active_or_paused_mission(opts) do
    case get_active_mission(opts) do
      {:ok, m} -> {:ok, m}
      _ -> get_paused_mission(opts)
    end
  end

  defp help do
    IO.puts("""
    ◄ INVADER ► - Agent Orchestrator

    USAGE:
      invade <command> [options]

    COMMANDS:
      start [PROMPT.md]      Start a new mission
        --sprite, -s NAME    Sprite to use (required)
        --waves, -w N        Max waves (default: 20)
        --duration, -d SEC   Max duration in seconds

      queue add PROMPT.md    Add mission to queue
        --sprite, -s NAME    Sprite to use (required)
        --priority, -p N     Queue priority (default: 0)

      queue list             Show pending missions

      status                 Show current status
      waves                  Show recent waves
      logs                   Show recent output

      save                   Create checkpoint
        --sprite, -s NAME    Sprite (required)
        --comment, -c TEXT   Checkpoint comment

      saves                  List checkpoints
        --sprite, -s NAME    Filter by sprite

      load CHECKPOINT_ID     Restore checkpoint
        --sprite, -s NAME    Sprite (required)

      pause                  Pause active mission
      resume                 Resume paused mission
      abort                  Abort mission

      dashboard              Open web dashboard
      help                   Show this help
    """)
  end

  defp puts_green(text), do: IO.puts(IO.ANSI.green() <> text <> IO.ANSI.reset())
  defp puts_red(text), do: IO.puts(IO.ANSI.red() <> text <> IO.ANSI.reset())
  defp puts_dim(text), do: IO.puts(IO.ANSI.faint() <> text <> IO.ANSI.reset())
end
