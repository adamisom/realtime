defmodule Realtime.Music.PatternMatcher do
  @moduledoc """
  Compares musical patterns for similarity/accuracy.
  """

  @doc """
  Check if response pattern matches call pattern.
  """
  def match?(call_pattern, response_pattern, opts \\ []) do
    accuracy = accuracy(call_pattern, response_pattern, opts)
    min_accuracy = Keyword.get(opts, :min_accuracy, 80.0)
    accuracy >= min_accuracy
  end

  @doc """
  Calculate accuracy percentage (0-100) between call and response patterns.
  ✅ FIX: Fixed invalid return statement and division by zero
  """
  def accuracy(call_pattern, response_pattern, opts \\ []) do
    timing_tolerance = Keyword.get(opts, :timing_tolerance_ms, 200)
    pitch_tolerance = Keyword.get(opts, :pitch_tolerance_semitones, 0)

    call_notes = normalize_pattern(call_pattern)
    response_notes = normalize_pattern(response_pattern)

    # ✅ FIX: Calculate length_ratio safely
    max_len = max(length(call_notes), length(response_notes))

    length_ratio =
      if max_len > 0 do
        min(length(call_notes), length(response_notes)) / max_len
      else
        0.0
      end

    # ✅ FIX: Early return using if expression (not return statement)
    if length_ratio < 0.5 do
      0.0
    else
      pairs = Enum.zip(call_notes, response_notes)

      scores =
        Enum.map(pairs, fn {call_note, response_note} ->
          note_score(call_note, response_note, timing_tolerance, pitch_tolerance)
        end)

      # ✅ FIX: Division by zero protection
      avg_score =
        if length(scores) > 0 do
          Enum.sum(scores) / length(scores)
        else
          0.0
        end

      avg_score * length_ratio
    end
  end

  @doc """
  Get detailed feedback on pattern match.
  """
  def feedback(call_pattern, response_pattern, opts \\ []) do
    accuracy_score = accuracy(call_pattern, response_pattern, opts)
    is_match = match?(call_pattern, response_pattern, opts)

    call_notes = normalize_pattern(call_pattern)
    response_notes = normalize_pattern(response_pattern)

    %{
      match: is_match,
      accuracy: accuracy_score,
      call_length: length(call_notes),
      response_length: length(response_notes),
      notes_matched: count_matched_notes(call_notes, response_notes, opts),
      total_notes: max(length(call_notes), length(response_notes))
    }
  end

  ## Private Functions

  defp normalize_pattern(pattern) when is_list(pattern) do
    Enum.map(pattern, fn note ->
      %{
        midi: Map.get(note, :midi) || Map.get(note, "midi"),
        timestamp: Map.get(note, :timestamp) || Map.get(note, "timestamp") || 0,
        duration: Map.get(note, :duration) || Map.get(note, "duration") || 500,
        velocity: Map.get(note, :velocity) || Map.get(note, "velocity") || 64
      }
    end)
  end

  defp note_score(call_note, response_note, timing_tolerance, pitch_tolerance) do
    pitch_diff = abs(call_note.midi - response_note.midi)

    pitch_score =
      if pitch_diff <= pitch_tolerance do
        1.0
      else
        max(0.0, 1.0 - (pitch_diff - pitch_tolerance) / 12.0)
      end

    timing_diff = abs(call_note.timestamp - response_note.timestamp)

    timing_score =
      if timing_diff <= timing_tolerance do
        1.0
      else
        max(0.0, 1.0 - (timing_diff - timing_tolerance) / 1000.0)
      end

    duration_diff = abs(call_note.duration - response_note.duration)

    duration_score =
      if duration_diff <= timing_tolerance do
        1.0
      else
        max(0.0, 1.0 - duration_diff / 1000.0)
      end

    pitch_score * 0.5 + timing_score * 0.3 + duration_score * 0.2
  end

  defp count_matched_notes(call_notes, response_notes, opts) do
    timing_tolerance = Keyword.get(opts, :timing_tolerance_ms, 200)
    pitch_tolerance = Keyword.get(opts, :pitch_tolerance_semitones, 0)

    pairs = Enum.zip(call_notes, response_notes)

    Enum.count(pairs, fn {call_note, response_note} ->
      pitch_diff = abs(call_note.midi - response_note.midi)
      timing_diff = abs(call_note.timestamp - response_note.timestamp)
      pitch_diff <= pitch_tolerance and timing_diff <= timing_tolerance
    end)
  end
end
