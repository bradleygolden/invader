defmodule Invader.Missions.ScheduleCalculator do
  @moduledoc """
  Calculates the next run time for scheduled missions based on their schedule configuration.
  """

  @day_map %{
    "mon" => 1,
    "tue" => 2,
    "wed" => 3,
    "thu" => 4,
    "fri" => 5,
    "sat" => 6,
    "sun" => 7
  }

  @doc """
  Calculates the next run time based on the mission's schedule configuration.

  Returns `{:ok, datetime}` or `{:ok, nil}` for one-time schedules that have run.
  Returns `{:error, reason}` for invalid configurations.
  """
  def next_run_at(mission, from \\ DateTime.utc_now())

  def next_run_at(%{schedule_enabled: false}, _from), do: {:ok, nil}

  def next_run_at(%{schedule_type: :once}, _from) do
    # One-time schedules don't repeat - return nil after running
    {:ok, nil}
  end

  def next_run_at(%{schedule_type: :hourly, schedule_minute: minute}, from) do
    minute = minute || 0

    # Find the next occurrence of this minute
    next = next_hourly(from, minute)
    {:ok, next}
  end

  def next_run_at(%{schedule_type: :daily, schedule_hour: hour, schedule_minute: minute}, from) do
    hour = hour || 9
    minute = minute || 0

    next = next_daily(from, hour, minute)
    {:ok, next}
  end

  def next_run_at(
        %{
          schedule_type: :weekly,
          schedule_days: days,
          schedule_hour: hour,
          schedule_minute: minute
        },
        from
      ) do
    days = days || ["mon"]
    hour = hour || 9
    minute = minute || 0

    case next_weekly(from, days, hour, minute) do
      {:ok, next} -> {:ok, next}
      {:error, reason} -> {:error, reason}
    end
  end

  def next_run_at(%{schedule_type: :custom, schedule_cron: cron_expr}, from)
      when is_binary(cron_expr) do
    case parse_and_next_cron(cron_expr, from) do
      {:ok, next} -> {:ok, next}
      {:error, reason} -> {:error, reason}
    end
  end

  def next_run_at(%{schedule_type: type}, _from) when not is_nil(type) do
    {:error, "Missing required fields for schedule type: #{type}"}
  end

  def next_run_at(_mission, _from), do: {:ok, nil}

  # Calculate next hourly occurrence
  defp next_hourly(from, target_minute) do
    current_minute = from.minute
    current_second = from.second

    if current_minute < target_minute or (current_minute == target_minute and current_second == 0) do
      # Later this hour
      %{from | minute: target_minute, second: 0, microsecond: {0, 6}}
    else
      # Next hour
      from
      |> DateTime.add(1, :hour)
      |> Map.put(:minute, target_minute)
      |> Map.put(:second, 0)
      |> Map.put(:microsecond, {0, 6})
    end
  end

  # Calculate next daily occurrence
  defp next_daily(from, target_hour, target_minute) do
    target_time = Time.new!(target_hour, target_minute, 0)
    current_time = DateTime.to_time(from)

    if Time.compare(current_time, target_time) == :lt do
      # Later today
      %{from | hour: target_hour, minute: target_minute, second: 0, microsecond: {0, 6}}
    else
      # Tomorrow
      from
      |> DateTime.add(1, :day)
      |> Map.put(:hour, target_hour)
      |> Map.put(:minute, target_minute)
      |> Map.put(:second, 0)
      |> Map.put(:microsecond, {0, 6})
    end
  end

  # Calculate next weekly occurrence
  defp next_weekly(from, days, target_hour, target_minute) do
    day_numbers =
      days
      |> Enum.map(&String.downcase/1)
      |> Enum.map(&Map.get(@day_map, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    if Enum.empty?(day_numbers) do
      {:error, "No valid days specified for weekly schedule"}
    else
      current_day = Date.day_of_week(DateTime.to_date(from))
      target_time = Time.new!(target_hour, target_minute, 0)
      current_time = DateTime.to_time(from)

      # Check if today is a valid day and we haven't passed the time yet
      today_valid =
        current_day in day_numbers and Time.compare(current_time, target_time) == :lt

      if today_valid do
        {:ok, %{from | hour: target_hour, minute: target_minute, second: 0, microsecond: {0, 6}}}
      else
        # Find next valid day
        days_ahead = find_next_day(current_day, day_numbers, current_time, target_time)

        next =
          from
          |> DateTime.add(days_ahead, :day)
          |> Map.put(:hour, target_hour)
          |> Map.put(:minute, target_minute)
          |> Map.put(:second, 0)
          |> Map.put(:microsecond, {0, 6})

        {:ok, next}
      end
    end
  end

  defp find_next_day(current_day, day_numbers, current_time, target_time) do
    # If current day is in the list but we've passed the time, look for the next occurrence
    same_day_passed =
      current_day in day_numbers and Time.compare(current_time, target_time) != :lt

    # Find the next day in the list that's after today
    next_day_in_week =
      day_numbers
      |> Enum.find(fn day ->
        if same_day_passed do
          day > current_day
        else
          day >= current_day
        end
      end)

    case next_day_in_week do
      nil ->
        # Wrap to next week - find first day
        first_day = List.first(day_numbers)
        7 - current_day + first_day

      day when day == current_day and not same_day_passed ->
        0

      day ->
        day - current_day
    end
  end

  # Parse cron expression and find next occurrence
  defp parse_and_next_cron(cron_expr, from) do
    case Crontab.CronExpression.Parser.parse(cron_expr) do
      {:ok, cron} ->
        naive_from = DateTime.to_naive(from)

        case Crontab.Scheduler.get_next_run_date(cron, naive_from) do
          {:ok, naive_next} ->
            {:ok, DateTime.from_naive!(naive_next, "Etc/UTC")}

          {:error, reason} ->
            {:error, "Failed to calculate next cron run: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Invalid cron expression: #{inspect(reason)}"}
    end
  end

  @doc """
  Builds a cron expression from schedule configuration for display purposes.
  """
  def to_cron_expression(%{schedule_type: :hourly, schedule_minute: minute}) do
    "#{minute || 0} * * * *"
  end

  def to_cron_expression(%{schedule_type: :daily, schedule_hour: hour, schedule_minute: minute}) do
    "#{minute || 0} #{hour || 9} * * *"
  end

  def to_cron_expression(%{
        schedule_type: :weekly,
        schedule_days: days,
        schedule_hour: hour,
        schedule_minute: minute
      }) do
    day_nums =
      (days || ["mon"])
      |> Enum.map(&String.downcase/1)
      |> Enum.map(&Map.get(@day_map, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.join(",")

    "#{minute || 0} #{hour || 9} * * #{day_nums}"
  end

  def to_cron_expression(%{schedule_type: :custom, schedule_cron: cron}) do
    cron || "* * * * *"
  end

  def to_cron_expression(_), do: nil

  @doc """
  Returns a human-readable description of the schedule.
  """
  def describe(%{schedule_enabled: false}), do: "Not scheduled"

  def describe(%{schedule_type: :once, next_run_at: next}) when not is_nil(next) do
    "Once at #{format_datetime(next)}"
  end

  def describe(%{schedule_type: :once}), do: "Once (completed)"

  def describe(%{schedule_type: :hourly, schedule_minute: minute}) do
    "Every hour at :#{String.pad_leading(to_string(minute || 0), 2, "0")}"
  end

  def describe(%{schedule_type: :daily, schedule_hour: hour, schedule_minute: minute}) do
    "Daily at #{format_time(hour || 9, minute || 0)}"
  end

  def describe(%{
        schedule_type: :weekly,
        schedule_days: days,
        schedule_hour: hour,
        schedule_minute: minute
      }) do
    day_names =
      (days || ["mon"])
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(", ")

    "Weekly on #{day_names} at #{format_time(hour || 9, minute || 0)}"
  end

  def describe(%{schedule_type: :custom, schedule_cron: cron}) do
    "Custom: #{cron}"
  end

  def describe(_), do: "Not scheduled"

  defp format_time(hour, minute) do
    h = String.pad_leading(to_string(hour), 2, "0")
    m = String.pad_leading(to_string(minute), 2, "0")
    "#{h}:#{m}"
  end

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end
end
