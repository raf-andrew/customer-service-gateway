# Customer Service Gateway

Lightweight Express.js API gateway that provides a unified entry point for all RAF domains to access the HelpdeskClient API running in webapp_core.

## Endpoints

- `GET /health` - Health check
- `/api/helpdesk/*` - Proxied to the upstream HelpdeskClient API (default: `http://localhost:8000/api`)

## Setup

```bash
cp .env.example .env
npm install
npm run dev
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| GATEWAY_PORT | 3100 | Port the gateway listens on |
| HELPDESK_API_URL | http://localhost:8000/api | Upstream HelpdeskClient API base URL |
| ALLOWED_ORIGINS | (none) | Comma-separated list of allowed CORS origins |
