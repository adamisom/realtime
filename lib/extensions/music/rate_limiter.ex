defmodule Realtime.Music.RateLimiter do
  @moduledoc """
  Rate limiter for music room note plays.

  Uses a sliding window algorithm to track note plays per student per room.
  """
  use GenServer

  require Logger

  ## Client API

  @doc """
  Check if a note play is allowed for a student in a room.

  Returns: {:ok, :allowed} or {:error, :rate_limit_exceeded}
  """
  def check_rate_limit(room_id, tenant_id, student_id, max_per_second \\ 10) do
    key = {room_id, tenant_id, student_id}

    case :ets.lookup(__MODULE__, key) do
      [] ->
        {:ok, :allowed}

      [{^key, timestamps}] ->
        now = System.system_time(:millisecond)
        # Last 1 second
        window_start = now - 1000

        # Filter timestamps within the window
        recent_timestamps = Enum.filter(timestamps, fn ts -> ts >= window_start end)

        if length(recent_timestamps) >= max_per_second do
          {:error, :rate_limit_exceeded}
        else
          {:ok, :allowed}
        end
    end
  end

  @doc """
  Record a note play event for rate limiting purposes.
  """
  def record_note_play(room_id, tenant_id, student_id) do
    key = {room_id, tenant_id, student_id}
    now = System.system_time(:millisecond)

    # Update ETS table with new timestamp
    case :ets.lookup(__MODULE__, key) do
      [] ->
        :ets.insert(__MODULE__, {key, [now]})

      [{^key, timestamps}] ->
        # Add new timestamp and keep only last 100 (to prevent unbounded growth)
        new_timestamps = [now | timestamps] |> Enum.take(100)
        :ets.insert(__MODULE__, {key, new_timestamps})
    end

    :ok
  end

  @doc """
  Start the rate limiter GenServer.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for storing rate limit data
    # Public table so channel processes can access it
    :ets.new(__MODULE__, [:set, :public, :named_table])

    # Schedule periodic cleanup of old entries
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Clean up entries older than 1 minute (no activity)
    now = System.system_time(:millisecond)
    # 1 minute ago
    cutoff = now - 60_000

    :ets.foldl(
      fn {key, timestamps}, _acc ->
        # Filter out old timestamps
        recent_timestamps = Enum.filter(timestamps, fn ts -> ts >= cutoff end)

        if length(recent_timestamps) == 0 do
          # Remove entry if no recent timestamps
          :ets.delete(__MODULE__, key)
        else
          # Update entry with only recent timestamps
          :ets.insert(__MODULE__, {key, recent_timestamps})
        end
      end,
      :ok,
      __MODULE__
    )

    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_cleanup do
    # Clean up every 30 seconds
    Process.send_after(self(), :cleanup, 30_000)
  end
end
