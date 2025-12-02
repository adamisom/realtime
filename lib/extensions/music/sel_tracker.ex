defmodule Realtime.Music.SelTracker do
  @moduledoc """
  Social-Emotional Learning (SEL) data tracker for music extension.
  
  Tracks:
  - Participation events (note plays, tempo changes, etc.)
  - Student reflections
  """
  require Logger

  alias Realtime.Repo

  @doc """
  Log a participation event.
  
  ## Examples
  
      iex> log_participation("MUSIC-1234", "tenant-1", "student-1", "note_played", %{midi: 60})
      :ok
  """
  def log_participation(room_id, tenant_id, student_id, event_type, event_data \\ %{}) do
    attrs = %{
      room_id: room_id,
      tenant_id: tenant_id,
      student_id: student_id,
      event_type: event_type,
      event_data: event_data,
      timestamp: DateTime.utc_now()
    }

    %Realtime.Music.Schemas.ParticipationEvent{}
    |> Realtime.Music.Schemas.ParticipationEvent.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _event} -> :ok
      {:error, changeset} ->
        Logger.error("Failed to log participation event: #{inspect(changeset.errors)}")
        :error
    end
  end

  @doc """
  Log a student reflection.
  
  ## Examples
  
      iex> log_reflection("MUSIC-1234", "tenant-1", "student-1", "I enjoyed playing with others", "post_session")
      :ok
  """
  def log_reflection(room_id, tenant_id, student_id, reflection_text, reflection_type \\ "post_session", metadata \\ %{}) do
    attrs = %{
      room_id: room_id,
      tenant_id: tenant_id,
      student_id: student_id,
      reflection_text: reflection_text,
      reflection_type: reflection_type,
      metadata: metadata
    }

    %Realtime.Music.Schemas.StudentReflection{}
    |> Realtime.Music.Schemas.StudentReflection.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _reflection} -> :ok
      {:error, changeset} ->
        Logger.error("Failed to log reflection: #{inspect(changeset.errors)}")
        :error
    end
  end
end

