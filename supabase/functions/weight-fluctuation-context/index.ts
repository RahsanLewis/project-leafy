import { cors, json } from '../_shared/http.ts'

// Compatibility tombstone for older app builds. Weight guidance now comes from
// the adaptive plan responses returned by the active weight/check-in endpoints.
Deno.serve((request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  return json({ error: 'Weight fluctuation context has been retired.' }, 410)
})
