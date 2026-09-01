#!/usr/bin/env -S deno run --allow-env --allow-net
import { createClient } from 'npm:@supabase/supabase-js@2'

// Out-of-band catalog_admin grants. Do not bootstrap membership from JWT email.

const [action, email] = Deno.args
if (!['grant', 'revoke', 'list'].includes(action ?? '')) {
  console.error('Usage: manage-admin-membership.ts grant|revoke|list [email]')
  Deno.exit(1)
}

const url = Deno.env.get('SUPABASE_URL')
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')
if (!url || !key) throw new Error('SUPABASE_URL and a service-role key are required.')
const admin = createClient(url, key, { auth: { persistSession: false } })

if (action === 'list') {
  const { data, error } = await admin.from('admin_memberships').select('user_id,role,active,created_at').order('created_at')
  if (error) throw error
  console.table(data)
  Deno.exit(0)
}

if (!email) throw new Error('An email address is required.')
const { data: users, error: usersError } = await admin.auth.admin.listUsers({ perPage: 1000 })
if (usersError) throw usersError
const user = users.users.find((candidate) => candidate.email?.toLowerCase() === email.toLowerCase())
if (!user) throw new Error(`No Supabase user exists for ${email}. Sign in once before granting access.`)

const { error } = await admin.from('admin_memberships').upsert({
  user_id: user.id,
  role: 'catalog_admin',
  active: action === 'grant',
}, { onConflict: 'user_id' })
if (error) throw error
console.log(`${action === 'grant' ? 'Granted' : 'Revoked'} catalog admin access for ${email}.`)
