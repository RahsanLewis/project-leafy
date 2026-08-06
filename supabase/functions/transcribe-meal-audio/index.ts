import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authorization = request.headers.get('Authorization') ?? ''
    const url = Deno.env.get('SUPABASE_URL')!
    const publishable = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!
    const auth = createClient(url, publishable, { global: { headers: { Authorization: authorization } } })
    const { data: { user }, error: authError } = await auth.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)
    const incoming = await request.formData()
    const audio = incoming.get('audio')
    if (!(audio instanceof File) || audio.size < 1) return json({ error: 'Record a meal description first.' }, 400)
    if (audio.size > 3 * 1024 * 1024) return json({ error: 'Keep voice descriptions under 60 seconds.' }, 413)
    const key = Deno.env.get('OPENAI_API_KEY')
    if (!key) return json({ error: 'AI voice transcription is not configured yet.' }, 503)
    const form = new FormData()
    form.append('file', audio, audio.name || 'meal.m4a')
    form.append('model', Deno.env.get('OPENAI_TRANSCRIBE_MODEL') ?? 'gpt-4o-mini-transcribe')
    form.append('prompt', 'The speaker is describing food, drinks, ingredients, portions, brands, and cooking methods for a nutrition log.')
    const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST', headers: { Authorization: `Bearer ${key}` }, body: form,
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload?.error?.message ?? 'The AI service could not transcribe that recording.')
    const transcript = String(payload.text ?? '').trim().slice(0, 2000)
    if (!transcript) throw new Error('No speech was detected. Try recording again.')
    return json({ transcript })
  } catch (error) {
    console.error('transcribe-meal-audio failed', error)
    return json({ error: error instanceof Error ? error.message : 'Unable to transcribe that recording.' }, 400)
  }
})
