import { createClient } from "npm:@supabase/supabase-js@2";
import { unauthorized } from "./http.ts";

export async function requireUser(request: Request) {
  const authorization = request.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) unauthorized();

  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SECRET_KEY");
  if (!url || !publishable || !secret) {
    throw new Error("Supabase is not configured.");
  }

  const auth = createClient(url, publishable, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error } = await auth.auth.getUser();
  if (error || !user) unauthorized();

  return {
    user,
    admin: createClient(url, secret, { auth: { persistSession: false } }),
    url,
  };
}

export async function requireCatalogAdmin(request: Request) {
  const context = await requireUser(request);
  const membership = await context.admin.from("admin_memberships").select(
    "role",
  ).eq(
    "user_id",
    context.user.id,
  ).eq("role", "catalog_admin").eq("active", true).maybeSingle();
  if (membership.error || !membership.data) unauthorized();
  return context;
}
