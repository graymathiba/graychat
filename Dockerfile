FROM node:20-slim
WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm install
COPY backend/ .
EXPOSE 3000
CMD ["npx", "tsx", "index.ts"]
