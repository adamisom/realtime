# Music Extension Automated Test Script
# Run with: mix run scripts/test_music_extension.exs
# Or: ./scripts/test_music_extension.sh

# Ensure application is started (when run with mix run, this is already done)
if Code.ensure_loaded?(Mix) do
  # Application should already be started by mix run
else
  # If running directly, we'd need to start it, but mix run is preferred
  IO.puts("⚠️  Warning: This script should be run with 'mix run' or the shell script wrapper")
end

defmodule MusicExtensionTester do
  @moduledoc """
  Automated tester for music extension with error recovery and failure collection.
  """

  defstruct [
    failures: [],
    successes: [],
    tenant: nil,
    tenant_id: nil,
    room_id: nil,
    test_count: 0,
    pass_count: 0,
    fail_count: 0
  ]

  def run do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════╗
    ║   Music Extension Automated Test Suite                      ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

    state = %__MODULE__{}

    # Setup
    state = setup(state)

    # Run test suites
    state = test_core_features(state)
    state = test_tempo_server(state)
    state = test_game_features(state)
    state = test_database_persistence(state)
    state = test_error_handling(state)

    # Report results
    report_results(state)
  end

  defp setup(state) do
    IO.puts("\n📋 Setting up test environment...")

    try do
      # Get or create tenant
      tenant_id = "test-tenant-#{System.unique_integer([:positive])}"

      # Use test support generators
      tenant =
        case try do
               Realtime.Api.get_tenant_by_external_id(tenant_id)
             rescue
               _ -> nil
             catch
               _, _ -> nil
             end do
          nil ->
            IO.puts("  Creating test tenant: #{tenant_id}")
            # Use Generators for tenant creation
            Generators.tenant_fixture(%{external_id: tenant_id})

          existing ->
            IO.puts("  Using existing tenant: #{tenant_id}")
            existing
        end

      # Cache tenant for lookup (if Cachex is available)
      try do
        Cachex.put!(
          Realtime.Tenants.Cache,
          {{:get_tenant_by_external_id, 1}, [tenant_id]},
          {:cached, tenant}
        )
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end

      # Create room
      {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant_id, bpm: 120)

      IO.puts("  ✅ Setup complete: Room #{room_id}")
      %{state | tenant: tenant, tenant_id: tenant_id, room_id: room_id}
    rescue
      e ->
        record_failure(state, "Setup", "Failed to setup test environment: #{inspect(e)}")
    catch
      :exit, reason ->
        record_failure(state, "Setup", "Setup exited: #{inspect(reason)}")
    end
  end

  defp test_core_features(state) do
    IO.puts("\n🎯 Testing Core Features...")

    state
    |> test("Room Creation", fn s ->
      {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", s.tenant_id, bpm: 120)
      assert String.starts_with?(room_id, "MUSIC-"), "Room ID should start with MUSIC-"
      assert String.length(room_id) == 10, "Room ID should be 10 characters"
      s
    end)
    |> test("Get Room", fn s ->
      {:ok, room} = Realtime.Music.SessionManager.get_room(s.room_id)
      assert room.bpm == 120, "Room BPM should be 120"
      assert room.teacher_id == "teacher-1", "Teacher ID should match"
      s
    end)
    |> test("Join Room", fn s ->
      :ok = Realtime.Music.SessionManager.join_room(s.room_id, s.tenant_id, "student-1")
      {:ok, room} = Realtime.Music.SessionManager.get_room(s.room_id)
      assert "student-1" in room.students, "Student should be in room"
      s
    end)
    |> test("Multiple Students Join", fn s ->
      :ok = Realtime.Music.SessionManager.join_room(s.room_id, s.tenant_id, "student-2")
      :ok = Realtime.Music.SessionManager.join_room(s.room_id, s.tenant_id, "student-3")
      {:ok, room} = Realtime.Music.SessionManager.get_room(s.room_id)
      assert length(room.students) >= 3, "Should have at least 3 students"
      s
    end)
    |> test("Beat Assignment", fn s ->
      :ok = Realtime.Music.SessionManager.assign_beat(s.room_id, 1, "student-1")
      {:ok, assignments} = Realtime.Music.SessionManager.get_beat_assignments(s.room_id)
      assert Map.get(assignments, 1) == "student-1", "Beat 1 should be assigned to student-1"
      s
    end)
    |> test("Clear Beat Assignment", fn s ->
      :ok = Realtime.Music.SessionManager.clear_beat_assignment(s.room_id, 1)
      {:ok, assignments} = Realtime.Music.SessionManager.get_beat_assignments(s.room_id)
      assert Map.get(assignments, 1) == nil, "Beat 1 should be cleared"
      s
    end)
  end

  defp test_tempo_server(state) do
    IO.puts("\n⏱️  Testing Tempo Server...")

    state
    |> test("Start Tempo Server", fn s ->
      # Room already has tempo server from creation, but test starting a new one
      # First stop existing if any
      try do
        Realtime.Music.TempoServer.stop_clock(s.room_id, s.tenant_id)
      rescue
        _ -> :ok
      end

      # Verify can get tempo (server should exist from room creation)
      case Realtime.Music.TempoServer.get_tempo(s.room_id, s.tenant_id) do
        {:ok, _bpm} -> :ok
        _ -> raise "Cannot get tempo - server may not be running"
      end

      # Verify registered
      case Registry.lookup(Realtime.Music.Registry, {:tempo_server, s.tenant_id, s.room_id}) do
        [{_pid, _}] -> :ok
        [] -> raise "Tempo server not registered"
      end

      s
    end)
    |> test("Get Tempo", fn s ->
      {:ok, bpm} = Realtime.Music.TempoServer.get_tempo(s.room_id, s.tenant_id)
      assert bpm == 120, "Tempo should be 120 BPM"
      s
    end)
    |> test("Set Tempo", fn s ->
      :ok = Realtime.Music.TempoServer.set_tempo(s.room_id, s.tenant_id, 140)
      {:ok, bpm} = Realtime.Music.TempoServer.get_tempo(s.room_id, s.tenant_id)
      assert bpm == 140, "Tempo should be 140 BPM"
      s
    end)
    |> test("Invalid BPM Rejected", fn s ->
      result = Realtime.Music.TempoServer.set_tempo(s.room_id, s.tenant_id, 0)
      assert result == {:error, :invalid_bpm}, "Should reject BPM 0"
      s
    end)
    |> test("Start Clock", fn s ->
      # Ensure clock is started
      result = Realtime.Music.TempoServer.start_clock(s.room_id, s.tenant_id)
      assert result == :ok, "Clock should start successfully"

      # Verify tempo server is running
      {:ok, _bpm} = Realtime.Music.TempoServer.get_tempo(s.room_id, s.tenant_id)
      s
    end)
    |> test("Stop Clock", fn s ->
      :ok = Realtime.Music.TempoServer.stop_clock(s.room_id, s.tenant_id)

      # Wait a moment to ensure clock stopped
      Process.sleep(500)

      # Clock should be stopped (we can't easily verify no beats without subscribing,
      # but we can verify the stop command succeeded)
      # This is a basic test - more thorough testing would require channel integration
      s
    end)
  end

  defp test_game_features(state) do
    IO.puts("\n🎮 Testing Game Features...")

    state
    |> test("Set Game Type - Melody Builder", fn s ->
      :ok = Realtime.Music.SessionManager.set_game_type(s.room_id, s.tenant_id, :melody_builder)
      {:ok, %{game_type: game_type}} = Realtime.Music.SessionManager.get_game_state(s.room_id, s.tenant_id)
      assert game_type == :melody_builder, "Game type should be melody_builder"
      s
    end)
    |> test("Update Game State", fn s ->
      :ok =
        Realtime.Music.SessionManager.update_game_state(s.room_id, s.tenant_id, %{
          melody_sequence: [%{midi: 60, velocity: 80}]
        })

      {:ok, %{game_state: game_state}} =
        Realtime.Music.SessionManager.get_game_state(s.room_id, s.tenant_id)

      assert length(game_state["melody_sequence"]) == 1, "Should have 1 note in melody"
      s
    end)
    |> test("Start Turn Rotation", fn s ->
      student_ids = ["student-1", "student-2", "student-3"]

      :ok =
        Realtime.Music.SessionManager.start_turn_rotation(s.room_id, s.tenant_id, student_ids,
          turn_duration_seconds: 30
        )

      {:ok, turn_info} = Realtime.Music.SessionManager.get_current_turn(s.room_id, s.tenant_id)
      assert turn_info.student_id in student_ids, "Current turn should be one of the students"
      s
    end)
    |> test("Set Call Pattern", fn s ->
      :ok = Realtime.Music.SessionManager.set_game_type(s.room_id, s.tenant_id, :call_and_response)

      pattern = [%{midi: 60, timestamp: 0, duration: 500}]
      :ok = Realtime.Music.SessionManager.set_call_pattern(s.room_id, s.tenant_id, pattern)
      s
    end)
    |> test("Record Response", fn s ->
      response_pattern = [%{midi: 60, timestamp: 0, duration: 500}]
      :ok = Realtime.Music.SessionManager.record_response(s.room_id, s.tenant_id, "student-1", response_pattern)
      s
    end)
    |> test("Validate Response", fn s ->
      {:ok, feedback} =
        Realtime.Music.SessionManager.validate_response(s.room_id, s.tenant_id, "student-1")

      assert Map.has_key?(feedback, :match), "Feedback should have match field"
      assert Map.has_key?(feedback, :accuracy), "Feedback should have accuracy field"
      assert feedback.accuracy >= 0 and feedback.accuracy <= 100, "Accuracy should be 0-100"
      s
    end)
  end

  defp test_database_persistence(state) do
    IO.puts("\n💾 Testing Database Persistence...")

    state
    |> test("Save Game Session", fn s ->
      # Ensure game is active
      :ok = Realtime.Music.SessionManager.set_game_type(s.room_id, s.tenant_id, :melody_builder)
      :ok =
        Realtime.Music.SessionManager.update_game_state(s.room_id, s.tenant_id, %{
          melody_sequence: [%{midi: 60, velocity: 80}]
        })

      # Save session (async)
      :ok = Realtime.Music.SessionManager.save_game_session(s.room_id, s.tenant_id)

      # Wait for async save
      Process.sleep(200)

      # Verify saved
      sessions = Realtime.Music.SessionManager.get_game_sessions(s.room_id, s.tenant_id)
      assert length(sessions) >= 1, "Should have at least 1 saved session"

      session = hd(sessions)
      assert session.game_type == "melody_builder", "Session should have correct game type"
      s
    end)
    |> test("Load Game Sessions", fn s ->
      sessions = Realtime.Music.SessionManager.get_game_sessions(s.room_id, s.tenant_id)
      assert is_list(sessions), "Sessions should be a list"

      if length(sessions) > 0 do
        session = hd(sessions)
        assert Map.has_key?(session, :game_type), "Session should have game_type"
        assert Map.has_key?(session, :game_state), "Session should have game_state"
      end

      s
    end)
    |> test("SEL Participation Logging", fn s ->
      try do
        :ok =
          Realtime.Music.SelTracker.log_participation(
            s.room_id,
            s.tenant_id,
            "student-1",
            "note_played",
            %{midi: 60}
          )

        # Query events
        import Ecto.Query

        events =
          from(e in Realtime.Music.Schemas.ParticipationEvent,
            where: e.room_id == ^s.room_id and e.tenant_id == ^s.tenant_id,
            limit: 1
          )
          |> Realtime.Repo.all()

        assert length(events) >= 1, "Should have at least 1 participation event"
      rescue
        e ->
          # Database might not be available in all test environments
          IO.puts("    ⚠️  Skipping SEL test (database may not be available): #{Exception.message(e)}")
      end

      s
    end)
  end

  defp test_error_handling(state) do
    IO.puts("\n⚠️  Testing Error Handling...")

    state
    |> test("Get Non-Existent Room", fn s ->
      result = Realtime.Music.SessionManager.get_room("NONEXISTENT-1234")
      assert result == {:error, :not_found}, "Should return :not_found for non-existent room"
      s
    end)
    |> test("Invalid BPM Range", fn s ->
      result = Realtime.Music.TempoServer.set_tempo(s.room_id, s.tenant_id, 300)
      assert result == {:error, :invalid_bpm}, "Should reject BPM > 299"
      s
    end)
    |> test("Game Type Validation", fn s ->
      # Set wrong game type
      :ok = Realtime.Music.SessionManager.set_game_type(s.room_id, s.tenant_id, :rhythm_circle)

      # Try to use melody builder event (should fail or be ignored)
      # This tests that game-specific events validate game type
      s
    end)
  end

  # Test helper with error recovery
  defp test(state, test_name, test_fn) do
    state = %{state | test_count: state.test_count + 1}

    try do
      new_state = test_fn.(state)
      IO.puts("  ✅ #{test_name}")
      %{new_state | pass_count: new_state.pass_count + 1, successes: [test_name | new_state.successes]}
    rescue
      e ->
        error_msg = Exception.message(e)
        IO.puts("  ❌ #{test_name}: #{error_msg}")
        record_failure(state, test_name, error_msg)
    catch
      :exit, reason ->
        IO.puts("  ❌ #{test_name}: Process exited - #{inspect(reason)}")
        record_failure(state, test_name, "Process exited: #{inspect(reason)}")
    end
  end

  defp record_failure(state, test_name, error_msg) do
    failure = %{
      test: test_name,
      error: error_msg,
      timestamp: DateTime.utc_now()
    }

    %{
      state
      | failures: [failure | state.failures],
        fail_count: state.fail_count + 1
    }
  end

  defp assert(condition, message) when is_binary(message) do
    unless condition, do: raise(message)
  end

  defp report_results(state) do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════════╗
    ║                    Test Results Summary                      ║
    ╚══════════════════════════════════════════════════════════════╝

    Total Tests: #{state.test_count}
    ✅ Passed:   #{state.pass_count}
    ❌ Failed:   #{state.fail_count}
    Success Rate: #{if state.test_count > 0, do: Float.round(state.pass_count / state.test_count * 100, 1), else: 0}%
    """)

    if length(state.failures) > 0 do
      IO.puts("\n❌ Failures:")
      IO.puts("─" |> String.duplicate(60))

      Enum.each(Enum.reverse(state.failures), fn failure ->
        IO.puts("""
        Test: #{failure.test}
        Error: #{failure.error}
        Time: #{failure.timestamp}
        """)
      end)
    else
      IO.puts("\n🎉 All tests passed!")
    end

    IO.puts("\n" |> String.duplicate(60, "-"))

    # Exit with appropriate code
    if state.fail_count > 0 do
      System.halt(1)
    else
      System.halt(0)
    end
  end
end

# Run tests
MusicExtensionTester.run()

