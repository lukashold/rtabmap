FROM node:24-alpine AS build
WORKDIR /app
RUN corepack enable
COPY tools/scan-workspace/package.json tools/scan-workspace/pnpm-lock.yaml tools/scan-workspace/pnpm-workspace.yaml ./tools/scan-workspace/
WORKDIR /app/tools/scan-workspace
RUN pnpm install --frozen-lockfile
WORKDIR /app
COPY tools/scan-workspace ./tools/scan-workspace
COPY LICENSE ./LICENSE
COPY app/ios/RTABMapApp/MeasurementGuide.json ./app/ios/RTABMapApp/MeasurementGuide.json
WORKDIR /app/tools/scan-workspace
RUN pnpm test && pnpm build

FROM node:24-alpine
WORKDIR /app
COPY --from=build /app/tools/scan-workspace/dist ./dist
COPY tools/scan-workspace/server.mjs tools/scan-workspace/reconstruction-proxy.mjs ./
RUN mkdir /data && chown node:node /data
USER node
ENV HOST=0.0.0.0 PORT=8080 DATA_DIR=/data
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD node -e "fetch('http://127.0.0.1:8080/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server.mjs"]
