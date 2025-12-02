defmodule Realtime.Music.Schemas.StudentReflection do
  @moduledoc """
  Schema for student reflections.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "_realtime"
  schema "student_reflections" do
    field(:room_id, :string)
    field(:tenant_id, :string)
    field(:student_id, :string)
    field(:reflection_text, :string)
    field(:reflection_type, :string)
    field(:metadata, :map)

    timestamps()
  end

  def changeset(reflection, attrs) do
    reflection
    |> cast(attrs, [:room_id, :tenant_id, :student_id, :reflection_text, :reflection_type, :metadata])
    |> validate_required([:room_id, :tenant_id, :student_id, :reflection_text])
  end
end
