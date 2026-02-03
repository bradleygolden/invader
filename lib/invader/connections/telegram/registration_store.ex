defmodule Invader.Connections.Telegram.RegistrationStore do
  @moduledoc """
  ETS-backed GenServer for temporary Telegram registration codes.

  When a user wants to connect their Telegram account:
  1. UI generates a unique code via `generate_code/1`
  2. User sends `/start <code>` to the bot
  3. Webhook looks up code via `lookup/1` and links the chat
  4. Codes expire after 10 minutes
  """
  use GenServer

  @table __MODULE__
  @ttl_ms :timer.minutes(10)
  @cleanup_interval_ms :timer.minutes(1)

  # Client API

  @doc """
  Start the registration store.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generate a unique registration code for a connection.

  Returns the code string that the user should send to the bot.
  """
  @spec generate_code(String.t()) :: String.t()
  def generate_code(connection_id) do
    code = generate_random_code()
    expires_at = System.monotonic_time(:millisecond) + @ttl_ms

    :ets.insert(@table, {code, connection_id, expires_at})
    code
  end

  @doc """
  Look up a registration code.

  Returns `{:ok, connection_id}` if valid, or `{:error, :not_found}` if
  the code doesn't exist or has expired.
  """
  @spec lookup(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def lookup(code) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, code) do
      [{^code, connection_id, expires_at}] when expires_at > now ->
        {:ok, connection_id}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Remove a registration code (called after successful registration).
  """
  @spec delete(String.t()) :: :ok
  def delete(code) do
    :ets.delete(@table, code)
    :ok
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_expired do
    now = System.monotonic_time(:millisecond)

    # Match all entries where expires_at <= now
    match_spec = [{{:"$1", :_, :"$2"}, [{:"=<", :"$2", now}], [:"$1"]}]
    expired_codes = :ets.select(@table, match_spec)

    Enum.each(expired_codes, &:ets.delete(@table, &1))
  end

  defp generate_random_code do
    :crypto.strong_rand_bytes(6)
    |> Base.encode32(case: :lower, padding: false)
    |> String.slice(0, 8)
  end
end
