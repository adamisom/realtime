defmodule Realtime.Repo.Migrations.CreateGameSessionsTable do
  use Ecto.Migration

  def change do
    # ⚠️ CRITICAL: Use "_realtime" prefix for all music extension tables
    create table(:game_sessions, primary_key: false, prefix: "_realtime") do
      add :id, :binary_id, primary_key: true
      add :room_id, :string, null: false
      add :tenant_id, :string, null: false
      add :game_type, :string, null: false
      add :game_state, :map, null: false
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:game_sessions, [:room_id, :tenant_id], prefix: "_realtime")
    create index(:game_sessions, [:tenant_id, :game_type], prefix: "_realtime")
    create index(:game_sessions, [:started_at], prefix: "_realtime")
  end
end

