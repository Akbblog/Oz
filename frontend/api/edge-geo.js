// Vercel Edge Function: GET /api/edge-geo
//
// Vercel knows where each request comes from but does not pass that on to
// the backend behind the /api rewrite. This returns it to the app, which
// sends it along with the visit beacon and the sign-up form.
//   { "country": "PK", "region": "PB", "city": "Lahore" }   (any may be null)
export const config = { runtime: 'edge' };

function text(value) {
  if (!value) return null;
  try {
    return decodeURIComponent(value);
  } catch (e) {
    return value;
  }
}

export default function handler(request) {
  const h = request.headers;
  const body = {
    country: text(h.get('x-vercel-ip-country')),
    region: text(h.get('x-vercel-ip-country-region')),
    city: text(h.get('x-vercel-ip-city')),
  };
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}
