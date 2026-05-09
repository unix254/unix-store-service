FROM ghcr.io/cirruslabs/flutter:stable AS flutter-builder

WORKDIR /flutter_app

# Copy only pubspec first to cache pub get layer
COPY flutter_app/pubspec.yaml flutter_app/pubspec.lock* ./
RUN flutter pub get && flutter precache --web

# Copy rest of Flutter source and build
COPY flutter_app/ .
RUN flutter build web --release --base-href / -v

# ── Stage 2: Node.js Runtime ───────────────────────────────────────────────
FROM node:20-alpine

# Bake EAT timezone in so business-day cutoff is always 07:00 EAT regardless
# of how the container is launched (compose, Docker Hub pull, or bare docker run).
ENV TZ=Africa/Nairobi

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

# Copy Flutter web build output → Express static directory
COPY --from=flutter-builder /flutter_app/build/web ./public/web

EXPOSE 5000

CMD ["node", "src/index.js"]
