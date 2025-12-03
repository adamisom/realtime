defmodule RealtimeWeb.MusicRoomChannelMelodyTest do
  use RealtimeWeb.ChannelCase, async: false

  alias RealtimeWeb.UserSocket

  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})

    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant.external_id, :melody_builder)
    :ok = Realtime.Music.SessionManager.join_room(room_id, tenant.external_id, "student-1")
    :ok = Realtime.Music.SessionManager.join_room(room_id, tenant.external_id, "student-2")

    teacher_jwt = Generators.generate_jwt_token(tenant, %{"role" => "teacher"})
    {:ok, teacher_socket} = connect(UserSocket, %{}, conn_opts(tenant, teacher_jwt))

    {:ok, _, teacher_socket} =
      subscribe_and_join(teacher_socket, "music_room:#{room_id}", %{"student_id" => "teacher-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    student1_jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
    {:ok, student1_socket} = connect(UserSocket, %{}, conn_opts(tenant, student1_jwt))

    {:ok, _, student1_socket} =
      subscribe_and_join(student1_socket, "music_room:#{room_id}", %{"student_id" => "student-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    {:ok, teacher_socket: teacher_socket, student1_socket: student1_socket, room_id: room_id, tenant: tenant}
  end

  defp conn_opts(tenant, token) do
    [
      connect_info: %{
        uri: URI.parse("https://#{tenant.external_id}.localhost:4000/socket/websocket"),
        x_headers: [{"x-api-key", token}]
      }
    ]
  end

  test "teacher can start melody building", %{teacher_socket: teacher_socket} do
    teacher_socket = push(teacher_socket, "start_melody", %{})
    assert_reply teacher_socket, :ok
    assert_broadcast "melody_started", %{}
  end

  test "student can add note when it's their turn", %{
    student1_socket: student1_socket,
    room_id: room_id,
    tenant: tenant
  } do
    # Start melody first
    :ok = Realtime.Music.SessionManager.start_turn_rotation(room_id, tenant.external_id, ["student-1", "student-2"], 60)

    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        melody_sequence: [],
        melody_state: :building
      })

    :ok = Realtime.Music.SessionManager.start_current_turn(room_id, tenant.external_id)

    student1_socket = push(student1_socket, "add_note", %{"midi" => 60, "velocity" => 80})

    assert_reply student1_socket, :ok
    assert_broadcast "note_added", %{note: %{midi: 60, velocity: 80}}
    assert_broadcast "turn_advanced", %{}
  end

  test "student cannot add note when it's not their turn", %{tenant: tenant, room_id: room_id} do
    # Setup: student-1's turn, but student-2 tries to add note
    :ok = Realtime.Music.SessionManager.start_turn_rotation(room_id, tenant.external_id, ["student-1", "student-2"], 60)

    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        melody_sequence: [],
        melody_state: :building
      })

    :ok = Realtime.Music.SessionManager.start_current_turn(room_id, tenant.external_id)

    student2_jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
    {:ok, student2_socket} = connect(UserSocket, %{}, conn_opts(tenant, student2_jwt))

    {:ok, _, student2_socket} =
      subscribe_and_join(student2_socket, "music_room:#{room_id}", %{"student_id" => "student-2"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    student2_socket = push(student2_socket, "add_note", %{"midi" => 60, "velocity" => 80})
    assert_reply student2_socket, :error, %{reason: "not_your_turn"}
  end

  test "teacher can play melody", %{teacher_socket: teacher_socket, room_id: room_id, tenant: tenant} do
    # Add some notes to melody
    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        melody_sequence: [
          %{midi: 60, velocity: 80, student_id: "student-1", timestamp: 1000, position: 0}
        ]
      })

    teacher_socket = push(teacher_socket, "play_melody", %{})
    assert_reply teacher_socket, :ok
    assert_broadcast "melody_playing", %{melody: _melody}
  end

  test "teacher cannot play empty melody", %{teacher_socket: teacher_socket} do
    teacher_socket = push(teacher_socket, "play_melody", %{})
    assert_reply teacher_socket, :error, %{reason: "melody_empty"}
  end
end
