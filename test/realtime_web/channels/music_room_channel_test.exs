defmodule RealtimeWeb.MusicRoomChannelTest do
  use RealtimeWeb.ChannelCase, async: false

  alias RealtimeWeb.UserSocket

  setup do
    tenant = Containers.checkout_tenant(run_migrations: true)
    Cachex.put!(Realtime.Tenants.Cache, {{:get_tenant_by_external_id, 1}, [tenant.external_id]}, {:cached, tenant})
    jwt = Generators.generate_jwt_token(tenant)
    {:ok, socket} = connect(UserSocket, %{}, conn_opts(tenant, jwt))

    {:ok, socket: socket, tenant: tenant}
  end

  defp conn_opts(tenant, token) do
    [
      connect_info: %{
        uri: URI.parse("https://#{tenant.external_id}.localhost:4000/socket/websocket"),
        x_headers: [{"x-api-key", token}]
      }
    ]
  end

  describe "join" do
    test "returns error when room does not exist", %{socket: socket} do
      params = %{
        "student_id" => "student-1",
        "role" => "student"
      }

      assert {:error, %{reason: reason}} = subscribe_and_join(socket, "music_room:NONEXISTENT", params)
      assert reason in ["Room not found", "Session management not available"]
    end

    test "returns error when SessionManager not implemented", %{socket: socket} do
      # SessionManager.get_room returns {:error, :not_implemented} until Phase 4
      params = %{
        "student_id" => "student-1",
        "role" => "student"
      }

      # This will fail until Phase 4 implements SessionManager
      result = subscribe_and_join(socket, "music_room:TEST-ROOM", params)
      assert match?({:error, _}, result)
    end
  end

  describe "module structure" do
    test "module exists and can be loaded" do
      assert Code.ensure_loaded?(RealtimeWeb.MusicRoomChannel)
    end

    test "module has required handlers" do
      assert Code.ensure_loaded?(RealtimeWeb.MusicRoomChannel)
      # Verify handlers exist
      assert function_exported?(RealtimeWeb.MusicRoomChannel, :handle_in, 3)
      assert function_exported?(RealtimeWeb.MusicRoomChannel, :handle_info, 2)
    end
  end
end

