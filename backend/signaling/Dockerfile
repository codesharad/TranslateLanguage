FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
EXPOSE 8080
CMD ["npx", "tsx", "src/index.ts"]
