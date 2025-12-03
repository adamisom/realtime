defmodule Realtime.Music.PatternMatcherTest do
  use ExUnit.Case, async: true

  alias Realtime.Music.PatternMatcher

  describe "accuracy/3" do
    test "returns 100% for identical patterns" do
      call = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      response = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]

      accuracy = PatternMatcher.accuracy(call, response)
      # Allow small tolerance for floating point
      assert accuracy >= 95.0
    end

    test "returns lower accuracy for different pitches" do
      call = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      response = [%{midi: 72, timestamp: 0, duration: 500, velocity: 80}]

      accuracy = PatternMatcher.accuracy(call, response)
      assert accuracy < 100.0
      assert accuracy >= 0.0
    end

    test "returns lower accuracy for different timing" do
      call = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      response = [%{midi: 60, timestamp: 300, duration: 500, velocity: 80}]

      accuracy = PatternMatcher.accuracy(call, response)
      assert accuracy < 100.0
      assert accuracy >= 0.0
    end

    test "handles patterns of different lengths" do
      call = [
        %{midi: 60, timestamp: 0, duration: 500, velocity: 80},
        %{midi: 62, timestamp: 500, duration: 500, velocity: 80}
      ]
      response = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]

      accuracy = PatternMatcher.accuracy(call, response)
      assert accuracy < 100.0
      assert accuracy >= 0.0
    end

    test "returns 0 for very different patterns" do
      call = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      response = [%{midi: 100, timestamp: 10000, duration: 50, velocity: 10}]

      accuracy = PatternMatcher.accuracy(call, response)
      assert accuracy < 50.0
    end

    test "handles empty patterns safely" do
      call = []
      response = []

      accuracy = PatternMatcher.accuracy(call, response)
      assert accuracy == 0.0
    end
  end

  describe "match?/3" do
    test "returns true for matching patterns" do
      call = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      response = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]

      assert PatternMatcher.match?(call, response) == true
    end

    test "returns false for non-matching patterns" do
      call = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      response = [%{midi: 100, timestamp: 10000, duration: 50, velocity: 10}]

      assert PatternMatcher.match?(call, response) == false
    end

    test "respects min_accuracy option" do
      call = [%{midi: 60, timestamp: 0, duration: 500, velocity: 80}]
      response = [%{midi: 61, timestamp: 10, duration: 490, velocity: 79}]

      # Should match with default 80% threshold
      assert PatternMatcher.match?(call, response, min_accuracy: 50.0) == true
      assert PatternMatcher.match?(call, response, min_accuracy: 99.0) == false
    end
  end

  describe "feedback/3" do
    test "returns detailed feedback" do
      call = [
        %{midi: 60, timestamp: 0, duration: 500, velocity: 80},
        %{midi: 62, timestamp: 500, duration: 500, velocity: 80}
      ]
      response = [
        %{midi: 60, timestamp: 0, duration: 500, velocity: 80},
        %{midi: 62, timestamp: 500, duration: 500, velocity: 80}
      ]

      feedback = PatternMatcher.feedback(call, response)

      assert feedback.match == true
      assert feedback.accuracy >= 99.0
      assert feedback.call_length == 2
      assert feedback.response_length == 2
      assert feedback.notes_matched == 2
      assert feedback.total_notes == 2
    end
  end
end

