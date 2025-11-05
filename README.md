# Label Studio on Railway (Deploy Template)

This repository lets you deploy **Label Studio** to Railway for multi-user collaborative annotation.

## Environment Variables (Railway → Variables)
- `LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK=true`
- `LABEL_STUDIO_USERNAME=admin`
- `LABEL_STUDIO_PASSWORD=admin123`
- `PORT=8080`

## How it works
The `Procfile` runs `bash start.sh`, which launches Label Studio listening on `0.0.0.0:$PORT`.

## Optional (PostgreSQL)
If you add a Railway PostgreSQL plugin, map these variables:
- `LABEL_STUDIO_DATABASE_ENGINE=postgresql`
- `LABEL_STUDIO_DATABASE_HOST=${PGHOST}`
- `LABEL_STUDIO_DATABASE_NAME=${PGDATABASE}`
- `LABEL_STUDIO_DATABASE_USER=${PGUSER}`
- `LABEL_STUDIO_DATABASE_PASSWORD=${PGPASSWORD}`
- `LABEL_STUDIO_DATABASE_PORT=${PGPORT}`

Then redeploy.
