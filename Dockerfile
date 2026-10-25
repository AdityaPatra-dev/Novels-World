# ==============================================================================
# Novels World - Production Multi-Stage Dockerfile
# Stage 1: Build the Flutter Web application
# Stage 2: Serve with lightweight, secure NGINX Alpine image
# ==============================================================================

FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Cache dependencies
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy source code and build web release
COPY . .
RUN flutter build web --release --no-wasm-dry-run

# ==============================================================================
# Stage 2: Production Web Server
# ==============================================================================
FROM nginx:alpine-slim

LABEL maintainer="Aditya Patra <adityapatraraj@gmail.com>"
LABEL org.opencontainers.image.title="Novels World"
LABEL org.opencontainers.image.description="Modern, feature-rich web novel reader & AI audiobook progressive web application."
LABEL org.opencontainers.image.url="https://github.com/AdityaPatra-dev/Novels-World"
LABEL org.opencontainers.image.source="https://github.com/AdityaPatra-dev/Novels-World"
LABEL org.opencontainers.image.version="1.1.0"

# Copy custom NGINX configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy compiled web assets from builder stage
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1/health || exit 1

CMD ["nginx", "-g", "daemon off;"]

