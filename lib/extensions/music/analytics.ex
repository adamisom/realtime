defmodule Realtime.Music.Analytics do
  @moduledoc """
  Analytics module for music room sessions.
  
  Provides functions to query and aggregate participation data.
  """
  import Ecto.Query
  alias Realtime.Music.Schemas.ParticipationEvent
  alias Realtime.Repo

  @doc """
  Get room statistics.
  
  Returns:
  - Total notes played
  - Notes per student
  - Notes per minute
  - Tempo change count
  - Session duration
  """
  def get_room_statistics(room_id, tenant_id) do
    now = DateTime.utc_now()
    
    # Get all events for this room
    events_query = from e in ParticipationEvent,
      where: e.room_id == ^room_id and e.tenant_id == ^tenant_id
    
    events = Repo.all(events_query)
    
    if length(events) == 0 do
      %{
        total_notes: 0,
        notes_per_minute: 0,
        tempo_changes: 0,
        session_duration_minutes: 0,
        unique_students: 0
      }
    else
      # Calculate session duration (first event to last event)
      timestamps = Enum.map(events, & &1.timestamp)
      first_event = Enum.min(timestamps, DateTime)
      last_event = Enum.max(timestamps, DateTime)
      duration_seconds = DateTime.diff(last_event, first_event, :second)
      duration_minutes = if duration_seconds > 0, do: max(1, div(duration_seconds, 60)), else: 1
      
      # Count notes (note_played events)
      note_events = Enum.filter(events, fn e -> e.event_type == "note_played" end)
      total_notes = length(note_events)
      
      # Count tempo changes
      tempo_changes = Enum.count(events, fn e -> e.event_type == "tempo_changed" end)
      
      # Unique students
      unique_students = events
        |> Enum.map(& &1.student_id)
        |> Enum.uniq()
        |> length()
      
      # Notes per minute
      notes_per_minute = if duration_minutes > 0, do: div(total_notes, duration_minutes), else: 0
      
      %{
        total_notes: total_notes,
        notes_per_minute: notes_per_minute,
        tempo_changes: tempo_changes,
        session_duration_minutes: duration_minutes,
        unique_students: unique_students
      }
    end
  end

  @doc """
  Get participation breakdown per student.
  """
  def get_participation_breakdown(room_id, tenant_id) do
    query = from e in ParticipationEvent,
      where: e.room_id == ^room_id and e.tenant_id == ^tenant_id,
      group_by: e.student_id,
      select: {e.student_id, count(e.id)}
    
    results = Repo.all(query)
    
    Enum.into(results, %{}, fn {student_id, count} -> {student_id, count} end)
  end

  @doc """
  Get activity over time (for charts).
  
  Groups events by time intervals (default 1 minute).
  """
  def get_activity_over_time(room_id, tenant_id, interval_minutes \\ 1) do
    query = from e in ParticipationEvent,
      where: e.room_id == ^room_id and e.tenant_id == ^tenant_id,
      select: %{
        timestamp: e.timestamp,
        event_type: e.event_type
      },
      order_by: e.timestamp
    
    events = Repo.all(query)
    
    if length(events) == 0 do
      []
    else
      # Group events by time intervals
      first_timestamp = events |> List.first() |> Map.get(:timestamp)
      
      events
      |> Enum.group_by(fn event ->
        # Calculate which interval this event belongs to
        seconds_since_start = DateTime.diff(event.timestamp, first_timestamp, :second)
        interval_seconds = interval_minutes * 60
        interval_number = div(seconds_since_start, interval_seconds)
        interval_number
      end)
      |> Enum.map(fn {interval_number, interval_events} ->
        interval_start = DateTime.add(first_timestamp, interval_number * interval_minutes * 60, :second)
        %{
          interval_start: interval_start,
          event_count: length(interval_events),
          note_count: Enum.count(interval_events, fn e -> e.event_type == "note_played" end)
        }
      end)
      |> Enum.sort_by(& &1.interval_start, DateTime)
    end
  end
end

