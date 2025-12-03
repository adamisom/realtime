defmodule RealtimeWeb.MusicRoomChannelCallResponseTest do
  use RealtimeWeb.ChannelCase, async: false

  alias RealtimeWeb.UserSocket

  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})

    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant.external_id, :call_and_response)

    teacher_jwt =
      Generators.generate_jwt_token(tenant, %{
        "role" => "teacher",
        "exp" => System.system_time(:second) + 100_000
      })

    {:ok, teacher_socket} = connect(UserSocket, %{}, conn_opts(tenant, teacher_jwt))

    {:ok, _, teacher_socket} =
      subscribe_and_join(teacher_socket, "music_room:#{room_id}", %{"student_id" => "teacher-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    student_jwt =
      Generators.generate_jwt_token(tenant, %{
        "role" => "student",
        "exp" => System.system_time(:second) + 100_000
      })

    {:ok, student_socket} = connect(UserSocket, %{}, conn_opts(tenant, student_jwt))

    {:ok, _, student_socket} =
      subscribe_and_join(student_socket, "music_room:#{room_id}", %{"student_id" => "student-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    {:ok, teacher_socket: teacher_socket, student_socket: student_socket, room_id: room_id, tenant: tenant}
  end

  defp conn_opts(tenant, token) do
    [
      connect_info: %{
        uri: URI.parse("https://#{tenant.external_id}.localhost:4000/socket/websocket"),
        x_headers: [{"x-api-key", token}]
      }
    ]
  end

  test "teacher can play call pattern", %{teacher_socket: teacher_socket} do
    pattern = [
      %{"midi" => 60, "timestamp" => 0, "duration" => 500},
      %{"midi" => 64, "timestamp" => 500, "duration" => 500}
    ]

    teacher_socket = push(teacher_socket, "play_call", %{"pattern" => pattern})

    assert_reply teacher_socket, :ok
    assert_broadcast "call_playing", %{pattern: ^pattern}
  end

  test "student can record response", %{student_socket: student_socket} do
    response_pattern = [%{midi: 60, timestamp: 0, duration: 500}]
    student_socket = push(student_socket, "record_response", %{"response" => response_pattern})

    assert_reply student_socket, :ok
    assert_broadcast "response_recorded", %{student_id: "student-1"}
  end

  test "teacher can validate response", %{teacher_socket: teacher_socket, room_id: room_id, tenant: tenant} do
    # Set call pattern and record response
    call_pattern = [%{midi: 60, timestamp: 0, duration: 500}]
    :ok = Realtime.Music.SessionManager.set_call_pattern(room_id, tenant.external_id, call_pattern)

    response_pattern = [%{midi: 60, timestamp: 0, duration: 500}]
    :ok = Realtime.Music.SessionManager.record_response(room_id, tenant.external_id, "student-1", response_pattern)

    teacher_socket = push(teacher_socket, "validate_response", %{"student_id" => "student-1"})
    assert_reply teacher_socket, :ok, feedback
    assert_broadcast "response_feedback", %{student_id: "student-1", feedback: ^feedback}
    assert feedback.match == true
    assert feedback.accuracy >= 90.0
  end

  test "student cannot validate response", %{student_socket: student_socket} do
    student_socket = push(student_socket, "validate_response", %{"student_id" => "student-1"})
    assert_reply student_socket, :error, %{reason: "unauthorized"}
  end
end
