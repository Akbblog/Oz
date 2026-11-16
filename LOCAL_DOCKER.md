# Local Docker check

The local stack uses a fresh SQLite database in a Docker volume. It does not connect to the MySQL URL in `backend/.env` or start the Cloudflare tunnel.

From this directory:

```powershell
docker compose --env-file backend/.env -f docker-compose.local.yml up -d --build
```

Open <http://127.0.0.1:8080>. The API is at <http://127.0.0.1:8001/api/health>. Sign in with username `admin` and the value of `ADMIN_PASSWORD` in `backend/.env`.

To reset that local admin password again, change `ADMIN_PASSWORD` in `backend/.env`, then run:

```powershell
docker compose --env-file backend/.env -f docker-compose.local.yml up -d --force-recreate backend
docker compose --env-file backend/.env -f docker-compose.local.yml exec backend python scripts/reset_admin_password.py --email admin@localhost.test --password-env ADMIN_PASSWORD
```

To stop the stack without deleting its local database:

```powershell
docker compose --env-file backend/.env -f docker-compose.local.yml down
```
