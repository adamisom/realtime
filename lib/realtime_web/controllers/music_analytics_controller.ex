defmodule RealtimeWeb.MusicAnalyticsController do
  @moduledoc """
  Controller for music room analytics.
  """
  use RealtimeWeb, :controller

  alias Realtime.Music.Analytics

  action_fallback(RealtimeWeb.FallbackController)

  def show(conn, %{"room_id" => room_id}) do
    tenant_id = conn.assigns.tenant
    
    statistics = Analytics.get_room_statistics(room_id, tenant_id)
    
    conn
    |> put_status(:ok)
    |> json(statistics)
  end

  def participation(conn, %{"room_id" => room_id}) do
    tenant_id = conn.assigns.tenant
    
    breakdown = Analytics.get_participation_breakdown(room_id, tenant_id)
    
    conn
    |> put_status(:ok)
    |> json(breakdown)
  end

  def activity(conn, %{"room_id" => room_id} = params) do
    tenant_id = conn.assigns.tenant
    interval_minutes = params
      |> Map.get("interval_minutes", "1")
      |> String.to_integer()
    
    activity_data = Analytics.get_activity_over_time(room_id, tenant_id, interval_minutes)
    
    conn
    |> put_status(:ok)
    |> json(activity_data)
  end
end

