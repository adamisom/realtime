defmodule RealtimeWeb.MusicRoomChannelVelocityTest do
  use RealtimeWeb.ChannelCase, async: false

  alias RealtimeWeb.UserSocket

  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)

    Cachex.put!(
      Realtime.Tenants.Cache,
      {{:get_tenant_by_external_id, 1}, [tenant.external_id]},
      {:cached, tenant}
    )

    jwt = Generators.generate_jwt_token(tenant)
    {:ok, socket} = connect(UserSocket, %{}, conn_opts(tenant, jwt))

    {:ok, room_id} =
      Realtime.Music.SessionManager.create_room("teacher-1", tenant.external_id, bpm: 120)

    {:ok, _, socket} = subscribe_and_join(socket, "music_room:#{room_id}", %{"student_id" => "student-1"})

    # Wait for beat_assignments message
    assert_receive %Phoenix.Socket.Message{event: "beat_assignments"}, 1000

    {:ok, socket: socket, room_id: room_id}
  end

  defp conn_opts(tenant, token) do
    [
      connect_info: %{
        uri: URI.parse("https://#{tenant.external_id}.localhost:4000/socket/websocket"),
        x_headers: [{"x-api-key", token}]
      }
    ]
  end

  test "play_note includes velocity in broadcast", %{socket: socket} do
    push(socket, "play_note", %{"midi" => 60, "velocity" => 100})

    assert_broadcast "student_note", %{
      midi: 60,
      velocity: 100,
      student_id: "student-1"
    }
  end

  test "play_note defaults to velocity 64 if not provided", %{socket: socket} do
    push(socket, "play_note", %{"midi" => 60})

    assert_broadcast "student_note", %{
      midi: 60,
      velocity: 64,
      student_id: "student-1"
    }
  end

  test "velocity is clamped to valid range (0-127)", %{socket: socket} do
    push(socket, "play_note", %{"midi" => 60, "velocity" => 200})

    assert_broadcast "student_note", %{
      midi: 60,
      velocity: 127,
      student_id: "student-1"
    }

    push(socket, "play_note", %{"midi" => 60, "velocity" => -10})

    assert_broadcast "student_note", %{
      midi: 60,
      velocity: 0,
      student_id: "student-1"
    }
  end
end
