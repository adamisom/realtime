defmodule Realtime.Music.TurnManager do
  @moduledoc """
  Manages turn-taking for games that require sequential actions.
  """

  defstruct [
    :current_turn,
    :queue,
    :turn_duration_seconds,
    :turn_start_time,
    :turn_state,
    :student_ids
  ]

  @doc """
  Start turn rotation with a list of student IDs.
  """
  def start_turn_rotation(student_ids, turn_duration_seconds \\ 30)
      when is_list(student_ids) and length(student_ids) > 0 do
    %__MODULE__{
      current_turn: List.first(student_ids),
      queue: tl(student_ids),
      turn_duration_seconds: turn_duration_seconds,
      turn_start_time: nil,
      turn_state: :waiting,
      student_ids: student_ids
    }
  end

  @doc """
  Start the current turn (begin timing).
  """
  def start_turn(turn_manager) do
    %{turn_manager | turn_start_time: System.system_time(:second), turn_state: :active}
  end

  @doc """
  Advance to the next turn (rotate queue).
  """
  def next_turn(turn_manager) do
    new_queue = turn_manager.queue ++ [turn_manager.current_turn]

    {new_current, remaining_queue} =
      case new_queue do
        [next | rest] -> {next, rest}
        [] -> {nil, []}
      end

    %{
      turn_manager
      | current_turn: new_current,
        queue: remaining_queue,
        turn_start_time: nil,
        turn_state: if(new_current, do: :waiting, else: :completed)
    }
  end

  @doc """
  Get the current turn student ID.
  """
  def get_current_turn(turn_manager) do
    turn_manager.current_turn
  end

  @doc """
  Calculate remaining time for current turn (in seconds).
  Returns nil if turn not started or completed.
  """
  def time_remaining(turn_manager) do
    case turn_manager.turn_state do
      :active ->
        # Handle nil turn_start_time (shouldn't happen, but defensive)
        if is_nil(turn_manager.turn_start_time) do
          nil
        else
          elapsed = System.system_time(:second) - turn_manager.turn_start_time
          remaining = turn_manager.turn_duration_seconds - elapsed
          max(0, remaining)
        end

      _ ->
        nil
    end
  end

  @doc """
  Check if a specific student can act (is it their turn?).
  """
  def can_act?(turn_manager, student_id) do
    turn_manager.current_turn == student_id and turn_manager.turn_state == :active
  end

  @doc """
  Check if turn has expired.
  """
  def turn_expired?(turn_manager) do
    case time_remaining(turn_manager) do
      nil -> false
      0 -> true
      _ -> false
    end
  end

  @doc """
  Reset turn rotation (start over from beginning).
  """
  def reset(turn_manager) do
    start_turn_rotation(turn_manager.student_ids, turn_manager.turn_duration_seconds)
  end

  @doc """
  Convert turn manager to map (for storage in game_state).
  """
  def to_map(turn_manager) do
    %{
      current_turn: turn_manager.current_turn,
      queue: turn_manager.queue,
      turn_duration_seconds: turn_manager.turn_duration_seconds,
      turn_start_time: turn_manager.turn_start_time,
      turn_state: turn_manager.turn_state,
      student_ids: turn_manager.student_ids
    }
  end

  @doc """
  Reconstruct turn manager from map.
  """
  def from_map(map) do
    %__MODULE__{
      current_turn: map.current_turn,
      queue: map.queue,
      turn_duration_seconds: map.turn_duration_seconds,
      turn_start_time: map.turn_start_time,
      turn_state: map.turn_state,
      student_ids: map.student_ids
    }
  end
end
