FROM node:20-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json index.ts ./
RUN npx tsc

FROM node:20-alpine AS runner
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY --from=builder /app/dist /app/dist

EXPOSE 3000

CMD ["node", "dist/index.js"]
