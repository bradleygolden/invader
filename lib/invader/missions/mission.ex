defmodule Invader.Missions.Mission do
  @moduledoc """
  A mission represents a queued autonomous task to run on a sprite.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Missions,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshStateMachine, AshOban]

  sqlite do
    table "missions"
    repo Invader.Repo
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start, from: :pending, to: :running
      transition :pause, from: :running, to: :pausing
      transition :confirm_pause, from: :pausing, to: :paused
      transition :resume, from: [:paused, :pausing], to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: [:running, :paused, :pausing], to: :failed
      transition :abort, from: [:running, :paused, :pausing, :pending], to: :aborted
      # Allow scheduled missions to restart from terminal states
      transition :run_scheduled, from: [:completed, :failed, :aborted, :pending], to: :running
    end
  end

  oban do
    triggers do
      trigger :run_scheduled_mission do
        scheduler_cron "* * * * *"
        action :run_scheduled
        where expr(schedule_enabled == true and not is_nil(next_run_at) and next_run_at <= now())
        read_action :read
        queue :missions
        worker_module_name Invader.Missions.Mission.ScheduledMissionWorker
        scheduler_module_name Invader.Missions.Mission.ScheduledMissionScheduler
      end
    end
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :create, action: :create
    define :update, action: :update
    define :start, action: :start
    define :pause, action: :pause
    define :confirm_pause, action: :confirm_pause
    define :resume, action: :resume
    define :complete, action: :complete
    define :fail, action: :fail
    define :abort, action: :abort
    define :run_scheduled, action: :run_scheduled
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :prompt_path,
        :prompt,
        :sprite_id,
        :priority,
        :max_waves,
        :max_duration,
        :schedule_enabled,
        :schedule_type,
        :schedule_cron,
        :schedule_hour,
        :schedule_minute,
        :schedule_days,
        :next_run_at,
        :scopes,
        :scope_preset_id
      ]

      validate fn changeset, _context ->
        prompt_path = Ash.Changeset.get_attribute(changeset, :prompt_path)
        prompt = Ash.Changeset.get_attribute(changeset, :prompt)

        if is_nil(prompt_path) and is_nil(prompt) do
          {:error, field: :prompt, message: "either prompt or prompt_path must be provided"}
        else
          :ok
        end
      end

      # Calculate initial next_run_at for scheduled missions
      change Invader.Missions.Changes.CalculateInitialNextRun
    end

    update :update do
      require_atomic? false

      accept [
        :prompt_path,
        :prompt,
        :priority,
        :max_waves,
        :max_duration,
        :schedule_enabled,
        :schedule_type,
        :schedule_cron,
        :schedule_hour,
        :schedule_minute,
        :schedule_days,
        :next_run_at,
        :scopes,
        :scope_preset_id
      ]

      validate attribute_equals(:status, :pending) do
        message "can only update pending missions"
      end

      # Recalculate next_run_at when schedule is updated
      change Invader.Missions.Changes.CalculateInitialNextRun
    end

    update :start do
      change transition_state(:running)
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :pause do
      change transition_state(:pausing)
      change set_attribute(:status, :pausing)
    end

    update :confirm_pause do
      change transition_state(:paused)
      change set_attribute(:status, :paused)
    end

    update :resume do
      change transition_state(:running)
      change set_attribute(:status, :running)
    end

    update :complete do
      change transition_state(:completed)
      change set_attribute(:status, :completed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_message]
      change transition_state(:failed)
      change set_attribute(:status, :failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :abort do
      change transition_state(:aborted)
      change set_attribute(:status, :aborted)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :run_scheduled do
      require_atomic? false

      # Reset mission state for re-run
      change set_attribute(:current_wave, 0)
      change set_attribute(:error_message, nil)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      change set_attribute(:finished_at, nil)
      change set_attribute(:last_scheduled_run_at, &DateTime.utc_now/0)

      # Transition to running state
      change transition_state(:run_scheduled)
      change set_attribute(:status, :running)

      # Calculate next run time and enqueue the mission
      change Invader.Missions.Changes.ScheduleNextRun
      change Invader.Missions.Changes.EnqueueLoopRunner
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :prompt_path, :string do
      allow_nil? true
      public? true
      description "Absolute path to PROMPT.md - read fresh each wave"
    end

    attribute :prompt, :string do
      allow_nil? true
      public? true
      description "Inline prompt text (alternative to prompt_path)"
    end

    attribute :priority, :integer do
      default 0
      public? true
    end

    attribute :max_waves, :integer do
      default 1
      public? true
      description "Maximum number of iterations"
    end

    attribute :max_duration, :integer do
      allow_nil? true
      public? true
      description "Maximum duration in seconds"
    end

    attribute :current_wave, :integer do
      default 0
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :running, :pausing, :paused, :completed, :failed, :aborted]
    end

    attribute :error_message, :string do
      allow_nil? true
      public? true
    end

    attribute :started_at, :utc_datetime do
      allow_nil? true
      public? true
    end

    attribute :finished_at, :utc_datetime do
      allow_nil? true
      public? true
    end

    # Scheduling attributes
    attribute :schedule_enabled, :boolean do
      default false
      public? true
      description "Whether this mission has scheduling enabled"
    end

    attribute :schedule_type, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:once, :hourly, :daily, :weekly, :custom]
      description "Type of schedule: once, hourly, daily, weekly, or custom cron"
    end

    attribute :schedule_cron, :string do
      allow_nil? true
      public? true
      description "Custom cron expression (for schedule_type: :custom)"
    end

    attribute :schedule_hour, :integer do
      allow_nil? true
      public? true
      constraints min: 0, max: 23
      description "Hour of day for daily/weekly schedules (0-23)"
    end

    attribute :schedule_minute, :integer do
      allow_nil? true
      public? true
      constraints min: 0, max: 59
      description "Minute of hour for scheduling (0-59)"
    end

    attribute :schedule_days, {:array, :string} do
      allow_nil? true
      public? true
      description "Days of week for weekly schedule: mon, tue, wed, thu, fri, sat, sun"
    end

    attribute :next_run_at, :utc_datetime do
      allow_nil? true
      public? true
      description "When this mission should next run"
    end

    attribute :last_scheduled_run_at, :utc_datetime do
      allow_nil? true
      public? true
      description "When this mission was last triggered by scheduler"
    end

    attribute :scopes, {:array, :string} do
      allow_nil? true
      public? true

      description "Array of scope strings for CLI access control (e.g., ['github:pr:*', 'github:issue:view'])"
    end

    timestamps()
  end

  relationships do
    belongs_to :sprite, Invader.Sprites.Sprite do
      allow_nil? false
    end

    belongs_to :scope_preset, Invader.Scopes.ScopePreset do
      allow_nil? true
      description "Optional preset that provides default scopes"
    end

    has_many :waves, Invader.Missions.Wave
    has_many :github_repos, Invader.Missions.GithubRepo
  end
end
