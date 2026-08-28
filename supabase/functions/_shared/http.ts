export const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }
export function json(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } }) }

export class HTTPError extends Error {
  constructor(readonly status: number, message: string) {
    super(message)
    this.name = 'HTTPError'
  }
}

export function unauthorized(): never {
  throw new HTTPError(401, 'Unauthorized')
}

export function errorResponse(error: unknown, fallback: string, defaultStatus = 400) {
  if (error instanceof HTTPError) return json({ error: error.message }, error.status)
  return json({ error: error instanceof Error ? error.message : fallback }, defaultStatus)
}
