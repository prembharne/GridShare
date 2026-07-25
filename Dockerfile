# GridShare Difficult Core - Production Dockerfile
FROM node:20-alpine

WORKDIR /app

# Install dependencies
RUN apk add --no-cache openssl libc6-compat
COPY package*.json ./
RUN npm ci --omit=dev

# Copy source
COPY src ./src
COPY prisma ./prisma

# Generate Prisma client
RUN npx prisma generate

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S gridshare -u 1001 -G nodejs

USER gridshare

EXPOSE 8080

CMD ["node", "src/server.js"]