defmodule RealtimeWeb.MusicRoomChannelImprovisationTest do
  use RealtimeWeb.ChannelCase, async: false

  alias RealtimeWeb.UserSocket

  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})

    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant.external_id, :improvisation_jam)
    :ok = Realtime.Music.SessionManager.join_room(room_id, tenant.external_id, "student-1")
    :ok = Realtime.Music.SessionManager.join_room(room_id, tenant.external_id, "student-2")

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

    student1_jwt =
      Generators.generate_jwt_token(tenant, %{
        "role" => "student",
        "exp" => System.system_time(:second) + 100_000
      })

    {:ok, student1_socket} = connect(UserSocket, %{}, conn_opts(tenant, student1_jwt))

    {:ok, _, student1_socket} =
      subscribe_and_join(student1_socket, "music_room:#{room_id}", %{"student_id" => "student-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    student2_jwt =
      Generators.generate_jwt_token(tenant, %{
        "role" => "student",
        "exp" => System.system_time(:second) + 100_000
      })

    {:ok, student2_socket} = connect(UserSocket, %{}, conn_opts(tenant, student2_jwt))

    {:ok, _, student2_socket} =
      subscribe_and_join(student2_socket, "music_room:#{room_id}", %{"student_id" => "student-2"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    {:ok,
     teacher_socket: teacher_socket,
     student1_socket: student1_socket,
     student2_socket: student2_socket,
     room_id: room_id,
     tenant: tenant}
  end

  defp conn_opts(tenant, token) do
    [
      connect_info: %{
        uri: URI.parse("https://#{tenant.external_id}.localhost:4000/socket/websocket"),
        x_headers: [{"x-api-key", token}]
      }
    ]
  end

  test "teacher can start improvisation", %{teacher_socket: teacher_socket} do
    teacher_socket = push(teacher_socket, "start_improvisation", %{"solo_duration_seconds" => 30})
    assert_reply teacher_socket, :ok
    assert_broadcast "improvisation_started", %{solo_duration: 30}
  end

  test "student can request solo when it's their turn", %{
    student1_socket: student1_socket,
    room_id: room_id,
    tenant: tenant
  } do
    # Start improvisation and set student-1 as current turn
    :ok = Realtime.Music.SessionManager.start_turn_rotation(room_id, tenant.external_id, ["student-1", "student-2"], 30)

    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        improvisation_state: :waiting,
        current_soloist: nil,
        solo_queue: ["student-1", "student-2"]
      })

    :ok = Realtime.Music.SessionManager.start_current_turn(room_id, tenant.external_id)

    student1_socket = push(student1_socket, "request_solo", %{})
    assert_reply student1_socket, :ok
    assert_broadcast "solo_granted", %{soloist: "student-1"}
  end

  test "student cannot request solo when it's not their turn", %{
    student2_socket: student2_socket,
    room_id: room_id,
    tenant: tenant
  } do
    # Start improvisation and set student-1 as current turn
    :ok = Realtime.Music.SessionManager.start_turn_rotation(room_id, tenant.external_id, ["student-1", "student-2"], 30)

    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        improvisation_state: :waiting,
        current_soloist: nil,
        solo_queue: ["student-1", "student-2"]
      })

    :ok = Realtime.Music.SessionManager.start_current_turn(room_id, tenant.external_id)

    student2_socket = push(student2_socket, "request_solo", %{})
    assert_reply student2_socket, :error, %{reason: "not_your_turn"}
  end

  test "teacher can assign solo to student", %{teacher_socket: teacher_socket} do
    teacher_socket = push(teacher_socket, "assign_solo", %{"student_id" => "student-1"})
    assert_reply teacher_socket, :ok
    assert_broadcast "solo_assigned", %{soloist: "student-1"}
  end

  test "only soloist can play notes during solo", %{
    student1_socket: student1_socket,
    student2_socket: student2_socket,
    room_id: room_id,
    tenant: tenant
  } do
    # Set student-1 as soloist
    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        current_soloist: "student-1",
        improvisation_state: :solo_active
      })

    # Student-1 can play
    student1_socket = push(student1_socket, "play_note", %{"midi" => 60, "velocity" => 80})
    assert_reply student1_socket, :ok

    # Student-2 cannot play
    student2_socket = push(student2_socket, "play_note", %{"midi" => 60, "velocity" => 80})
    assert_reply student2_socket, :error, %{reason: "only_soloist_can_play"}
  end

  test "teacher can end solo and advance turn", %{teacher_socket: teacher_socket, room_id: room_id, tenant: tenant} do
    # Set up turn rotation and solo
    :ok = Realtime.Music.SessionManager.start_turn_rotation(room_id, tenant.external_id, ["student-1", "student-2"], 30)

    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        current_soloist: "student-1",
        improvisation_state: :solo_active
      })

    teacher_socket = push(teacher_socket, "end_solo", %{})
    assert_reply teacher_socket, :ok
    assert_broadcast "solo_ended", %{next_turn: _turn_info}
  end
end
