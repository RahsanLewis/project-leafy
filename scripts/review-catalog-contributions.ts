#!/usr/bin/env -S deno run --allow-env --allow-net

const [command = 'list', id, ...rest] = Deno.args
const url = Deno.env.get('SUPABASE_URL')
const key = Deno.env.get('CATALOG_REVIEW_KEY')
if (!url || !key) throw new Error('Set SUPABASE_URL and CATALOG_REVIEW_KEY before reviewing contributions.')
const actions: Record<string, string> = { show: 'detail', approve: 'approve', changes: 'request_changes', reject: 'reject' }
const action = command === 'list' ? 'list' : actions[command]
if (!action) throw new Error('Usage: review-catalog-contributions.ts list | show ID | approve ID [reason] | changes ID reason | reject ID reason')
if (command !== 'list' && !id) throw new Error(`${command} requires a contribution ID.`)
const response = await fetch(`${url}/functions/v1/review-catalog-contribution`, {
  method: 'POST', headers: { 'Content-Type': 'application/json', 'x-leafy-admin-key': key },
  body: JSON.stringify({ action, contribution_id: id, reason: rest.join(' ') || undefined }),
})
const payload = await response.json()
if (!response.ok) throw new Error(payload.error ?? `Review request failed (${response.status}).`)
console.log(JSON.stringify(payload, null, 2))
