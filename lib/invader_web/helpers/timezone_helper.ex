defmodule InvaderWeb.TimezoneHelper do
  @moduledoc """
  Helper functions for timezone-aware datetime formatting.
  All data is stored in UTC; this module handles display conversion.
  """

  alias Invader.Settings

  @doc """
  Format a datetime according to the current timezone setting.
  Returns a formatted string like "Jan 31, 2:30 PM" or "Jan 31, 14:30 UTC".
  """
  def format_datetime(nil), do: "-"

  def format_datetime(datetime) do
    case Settings.timezone_mode() do
      :local -> format_local(datetime)
      :utc -> format_utc(datetime)
    end
  end

  @doc """
  Format a datetime for form inputs (ISO format).
  For :once schedule type datetime-local input.
  """
  def format_datetime_input(nil), do: ""

  def format_datetime_input(datetime) do
    case Settings.timezone_mode() do
      :local -> format_input_local(datetime)
      :utc -> format_input_utc(datetime)
    end
  end

  @doc """
  Parse a datetime input string according to timezone mode.
  Always returns UTC datetime for storage.
  """
  def parse_datetime_input(nil), do: nil
  def parse_datetime_input(""), do: nil

  def parse_datetime_input(input) when is_binary(input) do
    case Settings.timezone_mode() do
      :local -> parse_local_input(input)
      :utc -> parse_utc_input(input)
    end
  end

  @doc """
  Format relative time from now (e.g., "2h", "30m", "1d").
  """
  def format_relative(nil), do: "-"

  def format_relative(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(datetime, now)

    cond do
      diff_seconds < 0 -> "past"
      diff_seconds < 60 -> "#{diff_seconds}s"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h"
      true -> "#{div(diff_seconds, 86400)}d"
    end
  end

  @doc """
  Get timezone label for display.
  """
  def timezone_label do
    case Settings.timezone_mode() do
      :local ->
        case Settings.user_timezone() do
          nil -> "Local"
          tz -> short_timezone_name(tz)
        end

      :utc ->
        "UTC"
    end
  end

  defp format_utc(datetime) do
    format_string = time_format_string("UTC")
    Calendar.strftime(datetime, format_string)
  end

  defp format_local(datetime) do
    case Settings.user_timezone() do
      nil ->
        format_utc(datetime)

      timezone ->
        case DateTime.shift_zone(datetime, timezone) do
          {:ok, local_dt} ->
            format_string = time_format_string(nil)
            Calendar.strftime(local_dt, format_string)

          {:error, _} ->
            format_utc(datetime)
        end
    end
  end

  defp time_format_string(suffix) do
    suffix_str = if suffix, do: " #{suffix}", else: ""

    case Settings.time_format() do
      :"12h" -> "%b %d, %I:%M %p#{suffix_str}"
      :"24h" -> "%b %d, %H:%M#{suffix_str}"
    end
  end

  defp format_input_utc(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%dT%H:%M")
  end

  defp format_input_local(datetime) do
    case Settings.user_timezone() do
      nil ->
        format_input_utc(datetime)

      timezone ->
        case DateTime.shift_zone(datetime, timezone) do
          {:ok, local_dt} ->
            Calendar.strftime(local_dt, "%Y-%m-%dT%H:%M")

          {:error, _} ->
            format_input_utc(datetime)
        end
    end
  end

  defp parse_utc_input(input) do
    case NaiveDateTime.from_iso8601(input <> ":00") do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      {:error, _} -> nil
    end
  end

  defp parse_local_input(input) do
    case NaiveDateTime.from_iso8601(input <> ":00") do
      {:ok, naive} ->
        case Settings.user_timezone() do
          nil ->
            DateTime.from_naive!(naive, "Etc/UTC")

          timezone ->
            case DateTime.from_naive(naive, timezone) do
              {:ok, local_dt} ->
                case DateTime.shift_zone(local_dt, "Etc/UTC") do
                  {:ok, utc_dt} -> utc_dt
                  {:error, _} -> DateTime.from_naive!(naive, "Etc/UTC")
                end

              {:error, _} ->
                DateTime.from_naive!(naive, "Etc/UTC")

              {:ambiguous, first, _second} ->
                case DateTime.shift_zone(first, "Etc/UTC") do
                  {:ok, utc_dt} -> utc_dt
                  {:error, _} -> DateTime.from_naive!(naive, "Etc/UTC")
                end

              {:gap, just_before, _just_after} ->
                case DateTime.shift_zone(just_before, "Etc/UTC") do
                  {:ok, utc_dt} -> utc_dt
                  {:error, _} -> DateTime.from_naive!(naive, "Etc/UTC")
                end
            end
        end

      {:error, _} ->
        nil
    end
  end

  defp short_timezone_name(timezone) do
    case String.split(timezone, "/") do
      [_region, city | _] -> city |> String.replace("_", " ")
      [zone] -> zone
      _ -> timezone
    end
  end
end
