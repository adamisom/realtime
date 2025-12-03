defmodule RealtimeWeb.MusicRoomChannelDynamicsTest do
  use RealtimeWeb.ChannelCase, async: false

  alias RealtimeWeb.UserSocket

  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})

    {:ok, room_id} = Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)
    :ok = Realtime.Music.SessionManager.set_game_type(room_id, tenant.external_id, :dynamics_dance)

    teacher_jwt = Generators.generate_jwt_token(tenant, %{"role" => "teacher"})
    {:ok, teacher_socket} = connect(UserSocket, %{}, conn_opts(tenant, teacher_jwt))

    {:ok, _, teacher_socket} =
      subscribe_and_join(teacher_socket, "music_room:#{room_id}", %{"student_id" => "teacher-1"})

    # Wait for beat_assignments
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    student_jwt = Generators.generate_jwt_token(tenant, %{"role" => "student"})
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

  test "teacher can set dynamic pattern", %{teacher_socket: teacher_socket} do
    pattern = ["p", "mp", "mf", "f"]
    teacher_socket = push(teacher_socket, "set_dynamic_pattern", %{"pattern" => pattern})

    assert_reply teacher_socket, :ok
    assert_broadcast "dynamic_pattern_set", %{pattern: ^pattern}
  end

  test "teacher cannot set invalid dynamic pattern", %{teacher_socket: teacher_socket} do
    pattern = ["p", "invalid", "f"]
    teacher_socket = push(teacher_socket, "set_dynamic_pattern", %{"pattern" => pattern})

    assert_reply teacher_socket, :error, %{reason: "invalid_dynamic_pattern"}
  end

  test "teacher can set dynamic goal", %{teacher_socket: teacher_socket} do
    teacher_socket = push(teacher_socket, "set_dynamic_goal", %{"dynamic" => "mf"})

    assert_reply teacher_socket, :ok
    assert_broadcast "dynamic_goal_set", %{dynamic: "mf", velocity_range: {80, 90}}
  end

  test "student receives volume feedback when playing note", %{
    student_socket: student_socket,
    room_id: room_id,
    tenant: tenant
  } do
    # Set dynamic goal
    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        dynamic_goal: "mf",
        dynamic_velocity_range: {80, 90}
      })

    # Play note with velocity in range
    student_socket = push(student_socket, "play_note", %{"midi" => 60, "velocity" => 85})

    assert_reply student_socket, :ok

    assert_push "volume_feedback", %{
      velocity: 85,
      goal: "mf",
      in_range: true,
      target_range: {80, 90}
    }
  end

  test "student receives negative feedback when velocity out of range", %{
    student_socket: student_socket,
    room_id: room_id,
    tenant: tenant
  } do
    # Set dynamic goal
    :ok =
      Realtime.Music.SessionManager.update_game_state(room_id, tenant.external_id, %{
        dynamic_goal: "mf",
        dynamic_velocity_range: {80, 90}
      })

    # Play note with velocity out of range
    student_socket = push(student_socket, "play_note", %{"midi" => 60, "velocity" => 50})

    assert_reply student_socket, :ok

    assert_push "volume_feedback", %{
      velocity: 50,
      goal: "mf",
      in_range: false,
      target_range: {80, 90}
    }
  end
end
