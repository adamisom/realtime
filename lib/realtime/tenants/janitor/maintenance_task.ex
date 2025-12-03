defmodule Realtime.Tenants.Janitor.MaintenanceTask do
  @moduledoc """
  Perform maintenance on the messages table.
  * Delete old messages
  * Create new partitions
  """

  alias Realtime.Database
  alias Realtime.Messages
  alias Realtime.Tenants.Cache
  alias Realtime.Tenants.Migrations

  @spec run(String.t()) :: :ok | {:error, any}
  def run(tenant_external_id) do
    with %Realtime.Api.Tenant{} = tenant <- Cache.get_tenant_by_external_id(tenant_external_id),
         {:ok, conn} <- Database.connect(tenant, "realtime_janitor"),
         :ok <- Messages.delete_old_messages(conn),
         :ok <- Migrations.create_partitions(conn) do
      GenServer.stop(conn)
      :ok
    end
  end
end
