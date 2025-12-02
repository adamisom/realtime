defmodule Realtime.Music.Schemas.ParticipationEvent do
  @moduledoc """
  Schema for participation events.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "_realtime"
  schema "participation_events" do
    field(:room_id, :string)
    field(:tenant_id, :string)
    field(:student_id, :string)
    field(:event_type, :string)
    field(:event_data, :map)
    field(:timestamp, :utc_datetime)

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:room_id, :tenant_id, :student_id, :event_type, :event_data, :timestamp])
    |> validate_required([:room_id, :tenant_id, :student_id, :event_type, :timestamp])
  end
end
