# Generate JWT tokens for demo users
# Usage: Run in IEx console (since server is already running)
# Or: mix run --no-start demo/demo-generate-tokens.exs [tenant_id]

alias Realtime.Api
alias Realtime.Crypto

tenant_id = System.argv() |> List.first() || "test-tenant"

# Get or create tenant
tenant =
  case Api.get_tenant_by_external_id(tenant_id) do
    nil ->
      IO.puts("⚠️  Tenant '#{tenant_id}' not found. Creating...")

      case Api.create_tenant(%{
             external_id: tenant_id,
             name: tenant_id,
             jwt_secret: "demo-secret-key-1234567890123456"
           }) do
        {:ok, t} -> t
        error -> raise "Failed to create tenant: #{inspect(error)}"
      end

    t ->
      t
  end

secret = Crypto.decrypt!(tenant.jwt_secret)
signer = Joken.Signer.create("HS256", secret)

# Generate tokens
teacher_claims = %{
  role: "teacher",
  exp: System.system_time(:second) + 3600,
  iat: System.system_time(:second)
}

student_claims = %{
  role: "student",
  exp: System.system_time(:second) + 3600,
  iat: System.system_time(:second)
}

{:ok, _} = Joken.generate_claims(%{}, teacher_claims)
{:ok, teacher_jwt, _} = Joken.encode_and_sign(teacher_claims, signer)

{:ok, _} = Joken.generate_claims(%{}, student_claims)
{:ok, student_jwt, _} = Joken.encode_and_sign(student_claims, signer)

# Output in format that shell script can parse
IO.puts("TEACHER_TOKEN=#{teacher_jwt}")
IO.puts("STUDENT_TOKEN=#{student_jwt}")
