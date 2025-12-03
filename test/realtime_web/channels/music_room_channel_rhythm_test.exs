defmodule RealtimeWeb.MusicRoomChannelRhythmTest do
  use RealtimeWeb.ChannelCase, async: false

  alias RealtimeWeb.UserSocket

  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})

    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant.external_id, :rhythm_circle)

    teacher_jwt = Generators.generate_jwt_token(tenant, %{"role" => "teacher"})
    {:ok, teacher_socket} = connect(UserSocket, %{}, conn_opts(tenant, teacher_jwt))

    {:ok, _, teacher_socket} =
      subscribe_and_join(teacher_socket, "music_room:#{room_id}", %{"student_id" => "teacher-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    {:ok, teacher_socket: teacher_socket, room_id: room_id, tenant: tenant}
  end

  defp conn_opts(tenant, token) do
    [
      connect_info: %{
        uri: URI.parse("https://#{tenant.external_id}.localhost:4000/socket/websocket"),
        x_headers: [{"x-api-key", token}]
      }
    ]
  end

  test "teacher can assign pattern to student", %{teacher_socket: teacher_socket} do
    pattern = [%{midi: 60, duration: 500}, %{midi: 60, duration: 500}]
    teacher_socket = push(teacher_socket, "assign_pattern", %{"student_id" => "student-1", "pattern" => pattern})

    assert_reply teacher_socket, :ok
    assert_broadcast "pattern_assigned", %{student_id: "student-1", pattern: ^pattern}
  end

  test "student cannot assign pattern", %{tenant: tenant, room_id: room_id} do
    student_jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
    {:ok, student_socket} = connect(UserSocket, %{}, conn_opts(tenant, student_jwt))

    {:ok, _, student_socket} =
      subscribe_and_join(student_socket, "music_room:#{room_id}", %{"student_id" => "student-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    student_socket = push(student_socket, "assign_pattern", %{"student_id" => "student-2", "pattern" => []})
    assert_reply student_socket, :error, %{reason: "unauthorized"}
  end

  test "teacher can start pattern", %{teacher_socket: teacher_socket} do
    teacher_socket = push(teacher_socket, "pattern_start", %{})
    assert_reply teacher_socket, :ok
    assert_broadcast "pattern_started", %{}
  end

  test "pattern beats are broadcast when pattern is active", %{tenant: tenant, room_id: room_id} do
    # Set pattern state to active
    :ok = Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{pattern_state: :active})

    student_jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
    {:ok, student_socket} = connect(UserSocket, %{}, conn_opts(tenant, student_jwt))

    {:ok, _, _student_socket} =
      subscribe_and_join(student_socket, "music_room:#{room_id}", %{"student_id" => "student-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    # Start tempo server to generate beats
    :ok = Realtime.Music.TempoServer.set_tempo(room_id, tenant.external_id, 120)
    :ok = Realtime.Music.TempoServer.start_clock(room_id, tenant.external_id)

    # Wait for a beat
    assert_receive %Phoenix.Socket.Message{
                     event: "beat",
                     payload: %{beat: _beat_number}
                   },
                   1000

    # Should also receive pattern_beat
    assert_receive %Phoenix.Socket.Message{
                     event: "pattern_beat",
                     payload: %{beat: _beat_number}
                   },
                   1000
  end
end
