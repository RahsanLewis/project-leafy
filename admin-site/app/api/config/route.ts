export const dynamic = "force-dynamic";

export async function GET() {
  const supabaseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  const adminApiUrl = process.env.ADMIN_API_URL ?? process.env.NEXT_PUBLIC_ADMIN_API_URL ?? `${supabaseUrl}/functions/v1/review-catalog-contribution`;

  if (!supabaseUrl || !supabaseAnonKey || !adminApiUrl) {
    return Response.json({ error: "Dashboard configuration is unavailable." }, { status: 503 });
  }

  return Response.json({ supabaseUrl, supabaseAnonKey, adminApiUrl });
}
