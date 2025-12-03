defmodule Realtime.Music.Pattern do
  @moduledoc """
  Stores and manages musical patterns (sequences of notes with timing).
  """

  defstruct [:id, :name, :notes, :time_signature, :tempo, :pattern_type, :created_at]

  @doc """
  Create a new pattern.
  Notes format: [%{midi: 60, duration: 500, velocity: 80}, ...]
  """
  def create(name, notes, opts \\ []) do
    pattern_type = Keyword.get(opts, :pattern_type, :melody)
    time_signature = Keyword.get(opts, :time_signature, "4/4")
    tempo = Keyword.get(opts, :tempo, 120)

    notes_with_timing = add_timestamps(notes, 0)

    %__MODULE__{
      id: generate_id(),
      name: name,
      notes: notes_with_timing,
      time_signature: time_signature,
      tempo: tempo,
      pattern_type: pattern_type,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Schedule playback - returns list of scheduled broadcasts.
  """
  def schedule_playback(pattern, start_time_ms) do
    Enum.map(pattern.notes, fn note ->
      %{
        midi: note.midi,
        velocity: Map.get(note, :velocity, 64),
        timestamp: start_time_ms + note.timestamp,
        duration: note.duration
      }
    end)
  end

  @doc """
  Validate a pattern.
  """
  def validate(pattern) do
    cond do
      not is_list(pattern.notes) or pattern.notes == [] ->
        {:error, :empty_pattern}

      not Enum.all?(pattern.notes, &valid_note?/1) ->
        {:error, :invalid_notes}

      true ->
        :ok
    end
  end

  @doc """
  Get pattern duration in milliseconds.
  """
  def duration(pattern) do
    case List.last(pattern.notes) do
      nil -> 0
      last_note -> last_note.timestamp + last_note.duration
    end
  end

  @doc """
  Convert pattern to map for database storage.
  """
  def to_map(pattern) do
    %{
      id: pattern.id,
      name: pattern.name,
      notes: pattern.notes,
      time_signature: pattern.time_signature,
      tempo: pattern.tempo,
      pattern_type: Atom.to_string(pattern.pattern_type),
      created_at: pattern.created_at
    }
  end

  @doc """
  Reconstruct pattern from map.
  """
  def from_map(map) do
    %__MODULE__{
      id: map.id,
      name: map.name,
      notes: map.notes,
      time_signature: map.time_signature,
      tempo: map.tempo,
      pattern_type: String.to_existing_atom(map.pattern_type),
      created_at: map.created_at
    }
  end

  ## Private Functions

  defp add_timestamps(notes, start_time) do
    Enum.reduce(notes, {[], start_time}, fn note, {acc, current_time} ->
      note_with_timing = Map.put(note, :timestamp, current_time)
      {[note_with_timing | acc], current_time + note.duration}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp valid_note?(note) do
    midi = Map.get(note, :midi)
    duration = Map.get(note, :duration, 0)
    velocity = Map.get(note, :velocity, 64)

    is_integer(midi) and midi >= 0 and midi <= 127 and
      is_integer(duration) and duration > 0 and
      is_integer(velocity) and velocity >= 0 and velocity <= 127
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
