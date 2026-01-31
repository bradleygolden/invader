defmodule Invader.Settings do
  @moduledoc """
  In-memory settings storage using ETS.
  """
  use GenServer

  @table :invader_settings

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table])
    :ets.insert(@table, {:auto_start_queue, false})
    :ets.insert(@table, {:timezone_mode, :utc})
    :ets.insert(@table, {:user_timezone, nil})
    :ets.insert(@table, {:time_format, :"24h"})
    {:ok, %{}}
  end

  @doc """
  Get whether auto-start queue is enabled.
  """
  def auto_start_queue? do
    case :ets.lookup(@table, :auto_start_queue) do
      [{:auto_start_queue, value}] -> value
      [] -> false
    end
  end

  @doc """
  Set auto-start queue enabled/disabled.
  """
  def set_auto_start_queue(enabled) when is_boolean(enabled) do
    :ets.insert(@table, {:auto_start_queue, enabled})

    Phoenix.PubSub.broadcast(
      Invader.PubSub,
      "settings",
      {:settings_changed, :auto_start_queue, enabled}
    )

    :ok
  end

  @doc """
  Toggle auto-start queue.
  """
  def toggle_auto_start_queue do
    new_value = not auto_start_queue?()
    set_auto_start_queue(new_value)
    new_value
  end

  @doc """
  Get the current timezone display mode (:utc or :local).
  """
  def timezone_mode do
    case :ets.lookup(@table, :timezone_mode) do
      [{:timezone_mode, value}] -> value
      [] -> :utc
    end
  end

  @doc """
  Set timezone display mode.
  """
  def set_timezone_mode(mode) when mode in [:utc, :local] do
    :ets.insert(@table, {:timezone_mode, mode})

    Phoenix.PubSub.broadcast(
      Invader.PubSub,
      "settings",
      {:settings_changed, :timezone_mode, mode}
    )

    :ok
  end

  @doc """
  Toggle timezone mode between :utc and :local.
  """
  def toggle_timezone_mode do
    new_value = if timezone_mode() == :utc, do: :local, else: :utc
    set_timezone_mode(new_value)
    new_value
  end

  @doc """
  Get the user's timezone (e.g., "America/New_York").
  """
  def user_timezone do
    case :ets.lookup(@table, :user_timezone) do
      [{:user_timezone, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Set the user's timezone from browser detection.
  """
  def set_user_timezone(timezone) when is_binary(timezone) do
    :ets.insert(@table, {:user_timezone, timezone})

    Phoenix.PubSub.broadcast(
      Invader.PubSub,
      "settings",
      {:settings_changed, :user_timezone, timezone}
    )

    :ok
  end

  @doc """
  Get the time format (:"12h" or :"24h").
  """
  def time_format do
    case :ets.lookup(@table, :time_format) do
      [{:time_format, value}] -> value
      [] -> :"24h"
    end
  end

  @doc """
  Set time format.
  """
  def set_time_format(format) when format in [:"12h", :"24h"] do
    :ets.insert(@table, {:time_format, format})

    Phoenix.PubSub.broadcast(
      Invader.PubSub,
      "settings",
      {:settings_changed, :time_format, format}
    )

    :ok
  end

  @doc """
  Toggle time format between 12h and 24h.
  """
  def toggle_time_format do
    new_value = if time_format() == :"24h", do: :"12h", else: :"24h"
    set_time_format(new_value)
    new_value
  end
end
