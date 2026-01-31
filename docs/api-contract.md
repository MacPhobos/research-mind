# API Contract

## Health Check

**Endpoint**: `GET /health`

**Response** (200 OK):
```json
{
  "status": "ok",
  "name": "research-mind-service",
  "version": "0.1.0",
  "git_sha": "abc1234"
}
```

## Service Version

**Endpoint**: `GET /api/v1/version`

**Response** (200 OK):
```json
{
  "name": "research-mind-service",
  "version": "0.1.0",
  "git_sha": "abc1234"
}
```

## OpenAPI Schema

Available at: `GET /openapi.json`
