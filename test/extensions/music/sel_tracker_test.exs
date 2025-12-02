defmodule Realtime.Music.SelTrackerTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Realtime.Music.SelTracker

  setup do
    # Ensure we're using the test repo
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Realtime.Repo)
  end

  describe "log_participation/5" do
    test "logs a participation event" do
      room_id = "MUSIC-1234"
      tenant_id = "test-tenant"
      student_id = "student-1"
      event_type = "note_played"
      event_data = %{midi: 60}

      assert :ok = SelTracker.log_participation(room_id, tenant_id, student_id, event_type, event_data)

      # Verify event was saved
      query = from e in Realtime.Music.Schemas.ParticipationEvent,
        where: e.room_id == ^room_id and e.student_id == ^student_id

      assert [event] = Realtime.Repo.all(query)
      assert event.room_id == room_id
      assert event.tenant_id == tenant_id
      assert event.student_id == student_id
      assert event.event_type == event_type
      # JSONB stores maps with string keys
      assert event.event_data == %{"midi" => 60}
      assert event.timestamp != nil
    end

    test "logs tempo change event" do
      room_id = "MUSIC-1234"
      tenant_id = "test-tenant"
      teacher_id = "teacher-1"
      event_type = "tempo_changed"
      event_data = %{bpm: 140, changed_by: "teacher"}

      assert :ok = SelTracker.log_participation(room_id, tenant_id, teacher_id, event_type, event_data)

      query = from e in Realtime.Music.Schemas.ParticipationEvent,
        where: e.room_id == ^room_id and e.event_type == ^event_type

      assert [event] = Realtime.Repo.all(query)
      # JSONB stores maps with string keys
      assert event.event_data == %{"bpm" => 140, "changed_by" => "teacher"}
    end
  end

  describe "log_reflection/6" do
    test "logs a student reflection" do
      room_id = "MUSIC-1234"
      tenant_id = "test-tenant"
      student_id = "student-1"
      reflection_text = "I enjoyed playing with others"
      reflection_type = "post_session"
      metadata = %{mood: "happy"}

      assert :ok = SelTracker.log_reflection(room_id, tenant_id, student_id, reflection_text, reflection_type, metadata)

      # Verify reflection was saved
      query = from r in Realtime.Music.Schemas.StudentReflection,
        where: r.room_id == ^room_id and r.student_id == ^student_id

      assert [reflection] = Realtime.Repo.all(query)
      assert reflection.room_id == room_id
      assert reflection.tenant_id == tenant_id
      assert reflection.student_id == student_id
      assert reflection.reflection_text == reflection_text
      assert reflection.reflection_type == reflection_type
      # JSONB stores maps with string keys
      assert reflection.metadata == %{"mood" => "happy"}
    end

    test "uses default reflection type" do
      room_id = "MUSIC-1234"
      tenant_id = "test-tenant"
      student_id = "student-1"
      reflection_text = "Great session!"

      assert :ok = SelTracker.log_reflection(room_id, tenant_id, student_id, reflection_text)

      query = from r in Realtime.Music.Schemas.StudentReflection,
        where: r.room_id == ^room_id

      assert [reflection] = Realtime.Repo.all(query)
      assert reflection.reflection_type == "post_session"
    end
  end
end

