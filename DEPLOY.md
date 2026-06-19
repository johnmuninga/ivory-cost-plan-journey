# Deploying this OTP to Railway

This repo is set up to deploy to [Railway](https://railway.app) via Docker.
The transit graph is **built into the image** (Côte d'Ivoire OSM + SOTRA
GTFS), so the running container just loads and serves it.

## Files involved

- `Dockerfile` — 3-stage build: build JAR → download data + build graph → slim runtime.
- `railway.json` — tells Railway to use the Dockerfile and how to health-check.
- `.dockerignore` — keeps the build context small.

## One-time setup

1. Create a **new, empty repo** on your GitHub account (private is fine).
2. Push this project to it:
   ```bash
   git remote add deploy https://github.com/<you>/<repo>.git
   git push -u deploy <your-branch>
   ```
3. On Railway: **New Project → Deploy from GitHub repo** → pick that repo.
4. Railway detects `railway.json` and builds the Dockerfile automatically.

## Important: memory

OTP needs real RAM. The Côte d'Ivoire graph needs ~4 GB to build and
~2–3 GB to serve.

- **Build:** the `RUN java -Xmx4g ... --build` step needs that much during
  the image build. If Railway's builder OOMs, lower `-Xmx` or use a smaller
  OSM extract.
- **Runtime:** give the service a plan with **at least 4 GB**. The image
  uses `-XX:MaxRAMPercentage=75`, so it auto-sizes to whatever the
  container has — no fixed `-Xmx` to tweak.

## Changing the data

The OSM and GTFS URLs are `ARG`s in the `Dockerfile`:

- `OSM_URL` — Geofabrik extract
- `GTFS_URL` — the SOTRA export endpoint

To pull a **fresh GTFS feed**, just redeploy (Railway → Redeploy, or push a
commit). The graph is rebuilt from the latest data each image build.

## Verifying the deployment

Once live, Railway gives you a URL. Check:

- `https://<app>.up.railway.app/otp/` → JSON server info (also the healthcheck)
- `https://<app>.up.railway.app/otp/gtfs/v1` → GraphQL endpoint
- The debug client is served at the root `/`

## Local test of the same image

```bash
docker build -t otp-sotra .
docker run -p 8080:8080 otp-sotra
# then open http://localhost:8080
```
