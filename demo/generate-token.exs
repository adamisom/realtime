# Simple JWT token generator for demo
# Usage: mix run demo/generate-token.exs [tenant_id] [role]
# Example: mix run demo/generate-token.exs test-tenant teacher

alias Realtime.Api
alias Realtime.Crypto

tenant_id = System.argv() |> List.first() || "test-tenant"
role = System.argv() |> Enum.at(1) || "student"

# Get tenant
tenant =
  case Api.get_tenant_by_external_id(tenant_id) do
    nil ->
      IO.puts("⚠️  Tenant '#{tenant_id}' not found. Using default secret.")
      IO.puts("   To create tenant, run in IEx:")

      IO.puts(
        "   {:ok, tenant} = Realtime.Api.create_tenant(%{external_id: \"#{tenant_id}\", name: \"#{tenant_id}\", jwt_secret: \"demo-secret\"})"
      )

      nil

    t ->
      t
  end

# Generate token
secret =
  if tenant do
    Crypto.decrypt!(tenant.jwt_secret)
  else
    # Fallback for demo - use a simple secret
    # In production, always use proper tenant secrets
    "demo-secret-key-1234567890123456"
  end

signer = Joken.Signer.create("HS256", secret)

claims = %{
  role: role,
  exp: System.system_time(:second) + 3600,
  iat: System.system_time(:second)
}

{:ok, claims} = Joken.generate_claims(%{}, claims)
{:ok, jwt, _} = Joken.encode_and_sign(claims, signer)

IO.puts("\n=== JWT Token ===")
IO.puts("Role: #{role}")
IO.puts("Tenant: #{tenant_id}")
IO.puts("\nToken:")
IO.puts(jwt)
IO.puts("\n=== Usage ===")
IO.puts("Copy this token and use it in the demo's generateJWT function")
IO.puts("Or update demo/index.html to use this token directly")
