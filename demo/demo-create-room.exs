# Script to create a music room for testing
# Usage: mix run demo/demo-create-room.exs [teacher_id] [tenant_id] [bpm]
# Example: mix run demo/demo-create-room.exs teacher-1 test-tenant 30

alias Realtime.Music.SessionManager

teacher_id = System.argv() |> List.first() || "teacher-1"
tenant_id = System.argv() |> Enum.at(1) || "test-tenant"

bpm =
  System.argv()
  |> Enum.at(2)
  |> (fn
        nil -> 30
        val -> String.to_integer(val)
      end).()

case SessionManager.create_room(teacher_id, tenant_id, bpm: bpm) do
  {:ok, room_id} ->
    IO.puts("\n✅ Room created successfully!")
    IO.puts("Room ID: #{room_id}")
    IO.puts("Teacher: #{teacher_id}")
    IO.puts("Tenant: #{tenant_id}")
    IO.puts("BPM: #{bpm}")
    IO.puts("\n📋 Copy this room ID to use in the demo:")
    IO.puts(room_id)
    IO.puts("\n💡 Tip: Use demo/demo-launch-test-users.sh to open multiple test users")

  {:error, reason} ->
    IO.puts("\n❌ Failed to create room:")
    IO.inspect(reason)
    System.halt(1)
end
