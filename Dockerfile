# MacSync's website and install counter, for Coolify (see hindra/README.md).
FROM node:24-alpine AS build
WORKDIR /src/site
COPY site/package.json site/package-lock.json ./
RUN npm ci
WORKDIR /src
COPY . .
ARG SITE_URL=https://macsync.hindra.studio/
RUN cd site && SITE_URL=$SITE_URL npm run build && rm -f ../docs/RELEASING.md

FROM node:24-alpine
WORKDIR /srv
COPY hindra/server.mjs ./
COPY --from=build /src/docs ./site
RUN mkdir /data && chown node:node /data
USER node
ENV NODE_ENV=production PORT=3000 SITE_DIR=/srv/site DATA_DIR=/data
VOLUME /data
EXPOSE 3000
HEALTHCHECK CMD wget -qO- http://127.0.0.1:3000/healthz || exit 1
CMD ["node", "server.mjs"]
