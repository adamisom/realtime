defmodule Realtime.Repo.Migrations.CreateMusicPatternsTable do
  use Ecto.Migration

  def change do
    # ⚠️ CRITICAL: Use "_realtime" prefix for all music extension tables
    # This ensures proper schema isolation in multi-tenant system
    create table(:music_patterns, primary_key: false, prefix: "_realtime") do
      add :id, :binary_id, primary_key: true
      add :room_id, :string
      add :tenant_id, :string, null: false
      add :pattern_type, :string, null: false
      add :pattern_data, :map, null: false
      add :name, :string
      add :time_signature, :string
      add :tempo, :integer
      add :created_by, :string

      timestamps()
    end

    create index(:music_patterns, [:room_id, :tenant_id], prefix: "_realtime")
    create index(:music_patterns, [:tenant_id, :pattern_type], prefix: "_realtime")
  end
end

