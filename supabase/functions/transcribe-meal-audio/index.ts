import { cors, json } from '../_shared/http.ts'

// Compatibility tombstone for older app builds. Meal descriptions are now
// submitted as text through estimate-meal; this endpoint must never process audio.
Deno.serve((request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  return json({ error: 'Meal audio transcription has been retired.' }, 410)
})
