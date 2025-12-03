defmodule Realtime.Music.TempoServer do
  @moduledoc """
  GenServer that maintains a tempo clock and broadcasts beat events.

  Each music room has its own TempoServer process.
  The server sends beat events at the specified BPM to all clients in the room.
  """
  use GenServer
  require Logger

  alias Realtime.Tenants

  ## Client API

  @doc """
  Start a tempo server for a room.
  """
  def start_link({room_id, bpm, tenant_id}) do
    GenServer.start_link(__MODULE__, {room_id, bpm, tenant_id}, name: via_tuple(room_id, tenant_id))
  end

  @doc """
  Get current tempo for a room.
  """
  def get_tempo(room_id, tenant_id) do
    GenServer.call(via_tuple(room_id, tenant_id), :get_tempo)
  end

  @doc """
  Set tempo for a room (BPM must be between 1 and 299).
  """
  def set_tempo(room_id, tenant_id, bpm) when bpm > 0 and bpm < 300 do
    GenServer.cast(via_tuple(room_id, tenant_id), {:set_tempo, bpm})
  end

  def set_tempo(_room_id, _tenant_id, _bpm) do
    {:error, :invalid_bpm}
  end

  @doc """
  Start the tempo clock.
  """
  def start_clock(room_id, tenant_id) do
    GenServer.cast(via_tuple(room_id, tenant_id), :start_clock)
  end

  @doc """
  Stop the tempo clock.
  """
  def stop_clock(room_id, tenant_id) do
    GenServer.cast(via_tuple(room_id, tenant_id), :stop_clock)
  end

  ## Server Callbacks

  @impl true
  def init({room_id, bpm, tenant_id}) do
    Logger.info("Starting tempo server for room #{room_id} (tenant: #{tenant_id}) at #{bpm} BPM")

    state = %{
      room_id: room_id,
      tenant_id: tenant_id,
      bpm: bpm,
      beat: 0,
      running: false,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_tempo, _from, state) do
    {:reply, {:ok, state.bpm}, state}
  end

  @impl true
  def handle_cast({:set_tempo, bpm}, state) do
    Logger.info("Setting tempo to #{bpm} BPM for room #{state.room_id}")

    # Cancel existing timer if running
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # Schedule next beat with new tempo if running
    # Use schedule_beat which calculates from current time
    new_timer_ref =
      if state.running do
        schedule_beat(bpm)
      else
        nil
      end

    {:noreply, %{state | bpm: bpm, timer_ref: new_timer_ref}}
  end

  @impl true
  def handle_cast(:start_clock, state) do
    Logger.info("Starting clock for room #{state.room_id}")

    # Use schedule_beat which calculates from current time
    timer_ref = schedule_beat(state.bpm)

    {:noreply, %{state | running: true, timer_ref: timer_ref, beat: 0}}
  end

  @impl true
  def handle_cast(:stop_clock, state) do
    Logger.info("Stopping clock for room #{state.room_id}")

    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    {:noreply, %{state | running: false, timer_ref: nil}}
  end

  @impl true
  def handle_info(:beat, state) do
    # Use Tenants.tenant_topic/3 to construct correct PubSub topic
    tenant_topic = Tenants.tenant_topic(state.tenant_id, "music_room:#{state.room_id}", true)

    Phoenix.PubSub.broadcast(
      Realtime.PubSub,
      tenant_topic,
      {:beat, state.beat}
    )

    # ✅ FIX: Recalculate from current time to prevent drift
    now = System.monotonic_time(:millisecond)
    ms_per_beat = div(60_000, state.bpm)
    next_beat_time = now + ms_per_beat
    timer_ref = schedule_beat_at(next_beat_time)

    {:noreply, %{state | beat: state.beat + 1, timer_ref: timer_ref}}
  end

  ## Private Functions

  defp schedule_beat_at(target_time) do
    now = System.monotonic_time(:millisecond)
    delay = max(0, target_time - now)
    Process.send_after(self(), :beat, delay)
  end

  defp schedule_beat(bpm) do
    now = System.monotonic_time(:millisecond)
    ms_per_beat = div(60_000, bpm)
    schedule_beat_at(now + ms_per_beat)
  end

  defp via_tuple(room_id, tenant_id) do
    {:via, Registry, {Realtime.Music.Registry, {:tempo_server, tenant_id, room_id}}}
  end
end
