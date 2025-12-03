defmodule Realtime.Music.PatternTest do
  use ExUnit.Case, async: true

  alias Realtime.Music.Pattern

  describe "create/3" do
    test "creates pattern with notes" do
      notes = [
        %{midi: 60, duration: 500, velocity: 80},
        %{midi: 62, duration: 500, velocity: 80},
        %{midi: 64, duration: 1000, velocity: 80}
      ]

      pattern = Pattern.create("Test Melody", notes)

      assert pattern.name == "Test Melody"
      assert length(pattern.notes) == 3
      assert pattern.tempo == 120
      assert pattern.pattern_type == :melody
      assert is_binary(pattern.id)
    end

    test "creates pattern with custom options" do
      notes = [%{midi: 60, duration: 500, velocity: 80}]

      pattern =
        Pattern.create("Test", notes,
          pattern_type: :rhythm,
          time_signature: "3/4",
          tempo: 140
        )

      assert pattern.pattern_type == :rhythm
      assert pattern.time_signature == "3/4"
      assert pattern.tempo == 140
    end

    test "adds timestamps to notes" do
      notes = [
        %{midi: 60, duration: 500, velocity: 80},
        %{midi: 62, duration: 500, velocity: 80}
      ]

      pattern = Pattern.create("Test", notes)

      assert Enum.at(pattern.notes, 0).timestamp == 0
      assert Enum.at(pattern.notes, 1).timestamp == 500
    end
  end

  describe "validate/1" do
    test "validates valid pattern" do
      notes = [%{midi: 60, duration: 500, velocity: 80}]
      pattern = Pattern.create("Test", notes)

      assert :ok = Pattern.validate(pattern)
    end

    test "returns error for empty pattern" do
      pattern = %Pattern{notes: []}

      assert {:error, :empty_pattern} = Pattern.validate(pattern)
    end

    test "returns error for invalid notes" do
      pattern = %Pattern{
        notes: [
          %{midi: 200, duration: 500, velocity: 80},
          %{midi: 60, duration: -100, velocity: 80}
        ]
      }

      assert {:error, :invalid_notes} = Pattern.validate(pattern)
    end
  end

  describe "duration/1" do
    test "calculates pattern duration" do
      notes = [
        %{midi: 60, duration: 500, velocity: 80},
        %{midi: 62, duration: 500, velocity: 80},
        %{midi: 64, duration: 1000, velocity: 80}
      ]

      pattern = Pattern.create("Test", notes)
      duration = Pattern.duration(pattern)

      # Last note timestamp (1000) + last note duration (1000) = 2000
      assert duration == 2000
    end

    test "returns 0 for empty pattern" do
      pattern = %Pattern{notes: []}
      assert Pattern.duration(pattern) == 0
    end
  end

  describe "schedule_playback/2" do
    test "schedules playback with timestamps" do
      notes = [
        %{midi: 60, duration: 500, velocity: 80},
        %{midi: 62, duration: 500, velocity: 80}
      ]

      pattern = Pattern.create("Test", notes)
      scheduled = Pattern.schedule_playback(pattern, 1000)

      assert length(scheduled) == 2
      assert Enum.at(scheduled, 0).timestamp == 1000
      assert Enum.at(scheduled, 1).timestamp == 1500
      assert Enum.at(scheduled, 0).midi == 60
      assert Enum.at(scheduled, 1).midi == 62
    end
  end

  describe "to_map/1 and from_map/1" do
    test "serializes and deserializes pattern" do
      notes = [%{midi: 60, duration: 500, velocity: 80}]
      pattern = Pattern.create("Test", notes)

      map = Pattern.to_map(pattern)
      restored = Pattern.from_map(map)

      assert restored.name == pattern.name
      assert restored.notes == pattern.notes
      assert restored.tempo == pattern.tempo
      assert restored.pattern_type == pattern.pattern_type
    end
  end
end
