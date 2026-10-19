FROM node:24-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund \
    && npm cache clean --force \
    && mkdir /data && chown node:node /data
COPY upstream/src/hub ./src/hub
COPY upstream/src/shared ./src/shared
COPY upstream/LICENSE ./LICENSE
ARG SOURCE_REVISION=unknown
ARG BUILD_REPOSITORY=https://github.com/ViewWholeWorld/token-monitor-hub
LABEL org.opencontainers.image.title="Token Monitor Node Hub" \
      org.opencontainers.image.source=$BUILD_REPOSITORY \
      org.opencontainers.image.revision=$SOURCE_REVISION \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.description="基于 Javis603/token-monitor 的独立 Node Hub 镜像"
ENV TOKEN_MONITOR_HOST=0.0.0.0 \
    TOKEN_MONITOR_PORT=17321 \
    TOKEN_MONITOR_DATA_FILE=/data/devices.json
USER node
EXPOSE 17321
CMD ["node", "src/hub/server.js"]
