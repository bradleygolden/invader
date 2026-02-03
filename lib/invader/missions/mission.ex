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
    initial_states [:pending, :provisioning]
    default_initial_state :pending

    transitions do
      # Sprite provisioning transitions
      transition :sprite_ready, from: :provisioning, to: :setup
      transition :provision_failed, from: :provisioning, to: :failed
      transition :setup_complete, from: :setup, to: :pending

      # Standard mission transitions
      transition :start, from: :pending, to: :running
      transition :pause, from: :running, to: :pausing
      transition :confirm_pause, from: :pausing, to: :paused
      transition :resume, from: [:paused, :pausing], to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: [:running, :paused, :pausing, :setup], to: :failed
      transition :abort, from: [:running, :paused, :pausing, :pending, :setup], to: :aborted
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
    define :create_with_sprite, action: :create_with_sprite
    define :update, action: :update
    define :start, action: :start
    define :pause, action: :pause
    define :confirm_pause, action: :confirm_pause
    define :resume, action: :resume
    define :complete, action: :complete
    define :fail, action: :fail
    define :abort, action: :abort
    define :run_scheduled, action: :run_scheduled
    define :sprite_ready, action: :sprite_ready
    define :provision_failed, action: :provision_failed
    define :setup_complete, action: :setup_complete
    define :update_waves, action: :update_waves
    define :update_prompt, action: :update_prompt
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
        :scope_preset_id,
        :agent_type,
        :agent_provider,
        :agent_api_key
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

      validate fn changeset, _context ->
        sprite_id = Ash.Changeset.get_attribute(changeset, :sprite_id)

        if is_nil(sprite_id) do
          {:error, field: :sprite_id, message: "is required"}
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

    update :update_waves do
      require_atomic? false
      accept [:max_waves]

      validate fn changeset, _context ->
        status = Ash.Changeset.get_attribute(changeset, :status)

        if status in [:completed, :failed, :aborted] do
          {:error, field: :status, message: "cannot update waves on completed/failed/aborted missions"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        max_waves = Ash.Changeset.get_attribute(changeset, :max_waves)
        current_wave = changeset.data.current_wave || 0

        if max_waves < current_wave do
          {:error, field: :max_waves, message: "cannot set max_waves below current wave (#{current_wave})"}
        else
          :ok
        end
      end
    end

    update :update_prompt do
      require_atomic? false
      accept [:prompt]

      validate fn changeset, _context ->
        status = Ash.Changeset.get_attribute(changeset, :status)

        if status in [:completed, :failed, :aborted] do
          {:error, field: :status, message: "cannot update prompt on completed/failed/aborted missions"}
        else
          :ok
        end
      end
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
      change transition_state(:running)
      change set_attribute(:status, :running)

      # Calculate next run time and enqueue the mission
      change Invader.Missions.Changes.ScheduleNextRun
      change Invader.Missions.Changes.EnqueueLoopRunner
    end

    # Create a mission that will auto-create its own sprite
    create :create_with_sprite do
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
        :scope_preset_id,
        :sprite_name,
        :sprite_lifecycle,
        :agent_type,
        :agent_command,
        :agent_provider,
        :agent_base_url,
        :agent_api_key
      ]

      change set_attribute(:sprite_auto_created, true)
      change set_attribute(:status, :provisioning)
      change set_attribute(:state, :provisioning)

      validate fn changeset, _context ->
        prompt_path = Ash.Changeset.get_attribute(changeset, :prompt_path)
        prompt = Ash.Changeset.get_attribute(changeset, :prompt)

        if is_nil(prompt_path) and is_nil(prompt) do
          {:error, field: :prompt, message: "either prompt or prompt_path must be provided"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        sprite_name = Ash.Changeset.get_attribute(changeset, :sprite_name)

        if is_nil(sprite_name) or sprite_name == "" do
          {:error,
           field: :sprite_name, message: "sprite_name is required when creating a new sprite"}
        else
          :ok
        end
      end

      change Invader.Missions.Changes.CalculateInitialNextRun
      change Invader.Missions.Changes.EnqueueSpriteProvisioner
    end

    # Sprite provisioning transitions
    update :sprite_ready do
      require_atomic? false
      accept [:sprite_id]

      change transition_state(:setup)
      change set_attribute(:status, :setup)
    end

    update :provision_failed do
      require_atomic? false
      accept [:error_message]

      change transition_state(:failed)
      change set_attribute(:status, :failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :setup_complete do
      require_atomic? false

      change transition_state(:pending)
      change set_attribute(:status, :pending)
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
      constraints one_of: [:pending, :provisioning, :setup, :running, :pausing, :paused, :completed, :failed, :aborted]
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

    # Sprite provisioning attributes
    attribute :sprite_name, :string do
      allow_nil? true
      public? true
      description "Name for auto-created sprite (e.g., mission-abc123)"
    end

    attribute :sprite_auto_created, :boolean do
      default false
      public? true
      description "Whether this mission auto-created its sprite"
    end

    attribute :sprite_lifecycle, :atom do
      default :keep
      public? true
      constraints one_of: [:keep, :destroy_on_complete, :destroy_on_delete]

      description "When to destroy auto-created sprite: keep, destroy_on_complete, destroy_on_delete"
    end

    # Coding agent configuration
    attribute :agent_type, :atom do
      default :claude_code
      public? true
      constraints one_of: [:claude_code, :gemini_cli, :openai_codex, :custom]
      description "Type of coding agent: claude_code, gemini_cli, openai_codex, custom"
    end

    attribute :agent_command, :string do
      allow_nil? true
      public? true
      description "Custom CLI command override (uses agent_type default if not set)"
    end

    attribute :agent_provider, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:anthropic_subscription, :anthropic_api, :zai]

      description "API provider: anthropic_subscription (login via console), anthropic_api (API key), zai (Z.ai proxy)"
    end

    attribute :agent_base_url, :string do
      allow_nil? true
      public? true
      description "Custom API base URL for custom providers"
    end

    attribute :agent_api_key, :string do
      allow_nil? true
      public? true
      sensitive? true
      description "API key for automated agent setup (encrypted)"
    end

    timestamps()
  end

  relationships do
    belongs_to :sprite, Invader.Sprites.Sprite do
      allow_nil? true
    end

    belongs_to :scope_preset, Invader.Scopes.ScopePreset do
      allow_nil? true
      description "Optional preset that provides default scopes"
    end

    has_many :waves, Invader.Missions.Wave
    has_many :github_repos, Invader.Missions.GithubRepo
  end
end
