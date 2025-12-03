defmodule Realtime.Music.Schemas.MusicPattern do
  @moduledoc """
  Ecto schema for music patterns stored in the database.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "_realtime"
  schema "music_patterns" do
    field :room_id, :string
    field :tenant_id, :string
    field :pattern_type, :string
    field :pattern_data, :map
    field :name, :string
    field :time_signature, :string
    field :tempo, :integer
    field :created_by, :string

    timestamps()
  end

  def changeset(pattern, attrs) do
    pattern
    |> cast(attrs, [
      :room_id,
      :tenant_id,
      :pattern_type,
      :pattern_data,
      :name,
      :time_signature,
      :tempo,
      :created_by
    ])
    |> validate_required([:tenant_id, :pattern_type, :pattern_data])
    |> validate_inclusion(:pattern_type, ["rhythm", "melody", "call"])
  end
end
