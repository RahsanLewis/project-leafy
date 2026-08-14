import { cors, json } from '../_shared/http.ts'

// Kept temporarily as a tombstone so older app builds fail closed. New clients do
// not expose this program and no action can create or restore a commercial grant.
Deno.serve((request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  return json({ error: 'The nutrition data program has been retired.' }, 410)
})
