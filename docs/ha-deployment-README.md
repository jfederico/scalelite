# High Availability (HA) Deployments Behind Proxy/Load Balancer

This guide covers configuration considerations and best practices for deploying Scalelite in a High Availability setup with a proxy or load balancer.

## Architecture Overview

In HA deployments, Scalelite is typically deployed behind an external proxy or load balancer:

```
Internet
    ↓
External Load Balancer (ALB/NLB/Nginx/etc)
    ↓
Scalelite API Cluster (Multiple Instances)
    ↓
Shared Database & Cache (PostgreSQL, Redis)
    ↓
BigBlueButton Server Pool
```

## Key Configuration for HA Deployments

### URL_HOST vs Public Hostname

In HA deployments, you must distinguish between:

1. **Internal hostname** (`URL_HOST`) - Used for DNS rebinding protection and internal communication
2. **Public hostname** - The external URL that BigBlueButton servers and clients use

### Environment Variables Setup

#### Direct/Single Instance Deployment (Simplest)
```bash
URL_HOST=sl.example.com
# No need to set ANALYTICS_CALLBACK_URL_HOST
```

#### HA Behind Proxy/Load Balancer (Recommended)
```bash
# Internal hostname for DNS rebinding protection
URL_HOST=scalelite-api

# Public hostname for analytics callbacks and external communication
ANALYTICS_CALLBACK_URL_HOST=sl.example.com
```

## Analytics Callback URL Fix

### The Problem

In HA deployments, analytics callbacks failed because:

1. `URL_HOST` was set to internal hostname (e.g., `scalelite-api`, internal IP)
2. Analytics callback URL was built using `URL_HOST`
3. BigBlueButton servers couldn't reach the internal hostname

Result: Analytics tracking failed with connection errors

### The Solution

Starting with this version, Scalelite supports the `ANALYTICS_CALLBACK_URL_HOST` environment variable:

- **Takes precedence** for analytics callback URL construction
- **Falls back to `URL_HOST`** if not set (backward compatible)
- **Independent** from DNS rebinding protection

### How It Works

File: `app/handlers/analytics_callback_event_handler.rb`

```ruby
def handle
  return if analytics_callback_url.nil?

  # Use ANALYTICS_CALLBACK_URL_HOST if set (for HA/proxy deployments)
  # Otherwise fall back to URL_HOST (for direct deployments)
  host_name = Rails.configuration.x.analytics_callback_url_host || Rails.configuration.x.url_host

  params['meta_analytics-callback-url'] = if tenant.present?
    "https://#{tenant.name}.#{host_name}/bigbluebutton/api/analytics_callback"
  else
    "https://#{host_name}/bigbluebutton/api/analytics_callback"
  end
  # ...
end
```

## HA Deployment Examples

### AWS ALB with Scalelite Cluster

```bash
# On all Scalelite instances
URL_HOST=scalelite-internal                          # Internal DNS name or IP
ANALYTICS_CALLBACK_URL_HOST=sl.example.com          # Public domain behind ALB
DATABASE_URL=postgres://user:pass@rds-endpoint:5432/scalelite
REDIS_URL=redis://elasticache-endpoint:6379
```

**How it works:**
- Clients connect to `sl.example.com` (public)
- Load balancer routes to internal Scalelite instances
- Analytics callbacks reach `https://sl.example.com/bigbluebutton/api/analytics_callback`
- BigBlueButton servers can resolve and reach the public hostname

### Kubernetes Ingress with Scalelite Pod

```yaml
env:
  - name: URL_HOST
    value: "scalelite-api.default.svc.cluster.local"  # Internal k8s DNS
  - name: ANALYTICS_CALLBACK_URL_HOST
    value: "sl.example.com"                           # External domain
  - name: DATABASE_URL
    value: "postgres://user:pass@postgres:5432/scalelite"
  - name: REDIS_URL
    value: "redis://redis:6379"
```

### Multiple Data Center Setup

```bash
# Primary Scalelite Cluster
URL_HOST=scalelite-cluster-1               # Internal identifier
ANALYTICS_CALLBACK_URL_HOST=scalelite-1.example.com  # Public endpoint

# Secondary Scalelite Cluster
URL_HOST=scalelite-cluster-2               # Internal identifier
ANALYTICS_CALLBACK_URL_HOST=scalelite-2.example.com  # Public endpoint
```

## Required Configuration for HA

### Shared PostgreSQL Database

```bash
DATABASE_URL=postgresql://user:password@db-host:5432/scalelite
```

Must be accessible from all Scalelite instances.

### Shared Redis Cache

```bash
REDIS_URL=redis://redis-host:6379
```

Must be accessible from all Scalelite instances.

### Shared LOADBALANCER_SECRET(s)

```bash
# Same LOADBALANCER_SECRET across all instances
LOADBALANCER_SECRET=your-shared-secret

# Optional: multiple secrets for different clients
LOADBALANCER_SECRETS=secret1:secret2:secret3
```

### Shared Recording Directory

If using recordings, must be on shared NFS or object storage:

```bash
SCALELITE_RECORDING_DIR=/mnt/nfs/scalelite-recordings
```

Or with S3:

```bash
SCALELITE_RECORDING_DIR=s3://bucket-name/scalelite-recordings
```

## DNS Configuration

### Required DNS Entries

```
# Public endpoint (clients and BBB servers connect here)
sl.example.com          A   <Load Balancer IP>

# Optional: Specific cluster endpoints
scalelite-1.example.com A   <ALB/NLB IP>
scalelite-2.example.com A   <ALB/NLB IP>
```

### Important: BigBlueButton Server Resolution

Ensure BigBlueButton servers can resolve `ANALYTICS_CALLBACK_URL_HOST`:

```bash
# On each BigBlueButton server, test:
nslookup sl.example.com  # Should resolve to load balancer IP
ping sl.example.com      # Should be reachable
```

## Monitoring and Troubleshooting

### Check Analytics Callback Success

```bash
# View logs for analytics callback processing
docker logs scalelite-api | grep "analytics_callback"

# In database, check CallbackData records
docker exec -it postgres psql -U postgres -c \
  "SELECT meeting_id, callback_attributes FROM callback_data LIMIT 5;"
```

### Verify URL_HOST Configuration

```bash
# Check environment variables in running container
docker exec scalelite-api env | grep -E 'URL_HOST|ANALYTICS'

# Should show:
# URL_HOST=scalelite-api (or internal hostname)
# ANALYTICS_CALLBACK_URL_HOST=sl.example.com (or public hostname)
```

### Test Analytics Callback Endpoint

```bash
# From BigBlueButton server or external client
curl -k https://sl.example.com/health_check

# Should return 200 OK
```

## Load Balancer Configuration

### Nginx

```nginx
upstream scalelite {
    server scalelite-api-1:3000;
    server scalelite-api-2:3000;
    server scalelite-api-3:3000;
    keepalive 32;
}

server {
    server_name sl.example.com;
    listen 443 ssl http2;

    ssl_certificate /etc/letsencrypt/live/sl.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sl.example.com/privkey.pem;

    location / {
        proxy_pass http://scalelite;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
```

### AWS ALB Health Check

```
Protocol: HTTP
Path: /health_check
Port: 3000
Healthy threshold: 2
Unhealthy threshold: 3
Timeout: 5 seconds
Interval: 30 seconds
```

## Best Practices

1. **Always set ANALYTICS_CALLBACK_URL_HOST in HA deployments** - Don't rely on the fallback
2. **Use internal DNS names for URL_HOST** - Easier to manage than IPs
3. **Ensure BigBlueButton servers can reach the public hostname** - Test connectivity
4. **Monitor analytics callback processing** - Check logs for failures
5. **Use shared secrets across instances** - Same LOADBALANCER_SECRET everywhere
6. **Use external database and cache** - Don't use embedded instances in cluster
7. **Configure proper health checks** - Load balancer must monitor instance health
8. **Enable sticky sessions if needed** - Some clients may require session persistence

## Backward Compatibility

The `ANALYTICS_CALLBACK_URL_HOST` configuration is fully backward compatible:

- If not set, Scalelite falls back to `URL_HOST` (existing behavior)
- Single-instance deployments don't need to set it
- HA deployments get the fix by setting the new variable
- No database migrations required

## Related Documentation

- [Configuration Reference](configuration-README.md)
- [Docker Deployment](docker-README.md)
- [Protected Recordings](protectedrecordings_README.md)
- [Dial-in Configuration](dialin-README.md)
