# syntax=docker/dockerfile:1.7

# ---------- Stage 1: install deps & run in a full node image ----------
FROM node:20-alpine AS deps
WORKDIR /app
# Only copy manifest files first so this layer is cached unless deps change
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --no-audit --no-fund

# ---------- Stage 2: minimal runtime image ----------
FROM node:20-alpine AS runtime

# Security hardening:
# - run as non-root (node:node user already exists in the alpine image, but
#   we pin explicit uid/gid for clarity and to satisfy image scanners)
# - drop package manager caches, no dev deps, no shell tools beyond base
# - apply latest Alpine security patches (OS-level CVEs, e.g. OpenSSL)
#   rather than relying solely on whatever the base image tag last baked in
# - strip npm/npx/yarn/corepack entirely: this container only ever runs
#   `node src/index.js`, it never invokes npm at runtime, so removing them
#   eliminates an entire class of findings (npm bundles its own large
#   dependency tree - tar, minimatch, glob, sigstore, etc. - purely for
#   its own CLI use, none of which this app touches) and shrinks the
#   attack surface generally
RUN apk update && apk upgrade --no-cache \
  && rm -rf /usr/local/lib/node_modules/npm \
            /usr/local/lib/node_modules/corepack \
            /usr/local/bin/npm \
            /usr/local/bin/npx \
            /usr/local/bin/corepack \
            /opt/yarn-* \
  && addgroup -g 1001 appgroup && adduser -D -u 1001 -G appgroup appuser

WORKDIR /app
ENV NODE_ENV=production \
    PORT=8080

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

USER appuser

EXPOSE 8080

# Simple container-level healthcheck (Cloud Run uses its own HTTP probes,
# this is useful for local docker-compose / debugging too)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD node -e "require('http').get('http://127.0.0.1:8080/healthz',(r)=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "src/index.js"]