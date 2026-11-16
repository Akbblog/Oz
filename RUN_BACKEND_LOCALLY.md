# Run the live backend on this computer

The Flutter frontend is already hosted on Vercel. Its `/api/*` requests go to `https://server.progresslms.io`, which is reached through the Cloudflare tunnel on this computer. Scraping jobs run inside the FastAPI backend process.

The backend-only stack uses the live MySQL URL and other backend settings in the ignored `backend/.env`. It does not start a local frontend or local MySQL server.

From `business_scraper_api`:

```powershell
docker compose --env-file backend/.env -f docker-compose.worker.yml up -d --build
docker compose --env-file backend/.env -f docker-compose.worker.yml ps
```

Check the API at `http://127.0.0.1:8001/api/health`, then check the public route at `https://server.progresslms.io/api/health` and the live frontend proxy at `https://infinity-leads.vercel.app/api/health`.

To inspect logs without displaying environment values:

```powershell
docker compose --env-file backend/.env -f docker-compose.worker.yml logs --tail 100 backend tunnel
```

To stop the backend and tunnel:

```powershell
docker compose --env-file backend/.env -f docker-compose.worker.yml down
```

Keep Docker Desktop and this computer running for the public backend to stay online. The current tunnel token came from a previously committed Compose file; rotate it in Cloudflare and update `TUNNEL_TOKEN` in `backend/.env`.
