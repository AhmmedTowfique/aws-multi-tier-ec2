FROM node:18-slim
RUN apt-get update && apt-get install -y --no-install-recommends tini && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/app
COPY package*.json ./
RUN npm ci && npm cache clean --force
COPY . .

# Use the built-in node user (already exists in node:18-slim)
RUN chown -R node:node /usr/local/app
USER node

ENV PORT=8000
EXPOSE 8000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]