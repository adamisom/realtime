defmodule Realtime.Repo.Migrations.CreateMusicSelTables do
  use Ecto.Migration

  def change do
    create table(:participation_events, primary_key: false, prefix: "_realtime") do
      add(:id, :binary_id, primary_key: true)
      add(:room_id, :string, null: false)
      add(:tenant_id, :string, null: false)
      add(:student_id, :string, null: false)
      # "note_played", "tempo_changed", etc.
      add(:event_type, :string, null: false)
      # JSONB for flexible event data
      add(:event_data, :map)
      add(:timestamp, :utc_datetime, null: false)

      timestamps()
    end

    create(index(:participation_events, [:room_id, :tenant_id], prefix: "_realtime"))
    create(index(:participation_events, [:student_id, :tenant_id], prefix: "_realtime"))
    create(index(:participation_events, [:timestamp], prefix: "_realtime"))

    create table(:student_reflections, primary_key: false, prefix: "_realtime") do
      add(:id, :binary_id, primary_key: true)
      add(:room_id, :string, null: false)
      add(:tenant_id, :string, null: false)
      add(:student_id, :string, null: false)
      add(:reflection_text, :text, null: false)
      # "post_session", "mid_session", etc.
      add(:reflection_type, :string)
      # JSONB for additional data
      add(:metadata, :map)

      timestamps()
    end

    create(index(:student_reflections, [:room_id, :tenant_id], prefix: "_realtime"))
    create(index(:student_reflections, [:student_id, :tenant_id], prefix: "_realtime"))
  end
end
