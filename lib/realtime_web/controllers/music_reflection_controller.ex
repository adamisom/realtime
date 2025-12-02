defmodule RealtimeWeb.MusicReflectionController do
  @moduledoc """
  Controller for student reflection submissions.
  """
  use RealtimeWeb, :controller

  alias Realtime.Music.SelTracker

  action_fallback(RealtimeWeb.FallbackController)

  def create(conn, %{"room_id" => room_id, "student_id" => student_id, "reflection_text" => reflection_text} = params) do
    tenant_id = conn.assigns.tenant
    reflection_type = Map.get(params, "reflection_type", "post_session")
    metadata = Map.get(params, "metadata", %{})

    case SelTracker.log_reflection(room_id, tenant_id, student_id, reflection_text, reflection_type, metadata) do
      :ok ->
        conn
        |> put_status(:created)
        |> json(%{status: "success", message: "Reflection logged"})

      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Failed to log reflection"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{status: "error", message: "Missing required fields: room_id, student_id, reflection_text"})
  end
end

