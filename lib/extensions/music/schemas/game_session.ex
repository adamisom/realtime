defmodule Realtime.Music.Schemas.GameSession do
  @moduledoc """
  Ecto schema for game sessions stored in the database.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "_realtime"
  schema "game_sessions" do
    field :room_id, :string
    field :tenant_id, :string
    field :game_type, :string
    field :game_state, :map
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :room_id,
      :tenant_id,
      :game_type,
      :game_state,
      :started_at,
      :completed_at
    ])
    |> validate_required([:room_id, :tenant_id, :game_type, :game_state])
    |> validate_inclusion(:game_type, [
      "rhythm_circle",
      "melody_builder",
      "dynamics_dance",
      "improvisation_jam",
      "call_and_response"
    ])
  end
end
