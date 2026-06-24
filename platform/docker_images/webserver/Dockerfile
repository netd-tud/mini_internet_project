FROM node:22-alpine AS hilbert-assets

WORKDIR /web-assets
COPY web-assets/package*.json ./
RUN npm ci
COPY web-assets ./
RUN npm run build


FROM python:3-alpine

# Basic debugging tools.
RUN apk add --no-cache tini bash bash-completion util-linux coreutils libqrencode-tools \
                       binutils findutils grep vim nano tzdata \
                       iputils net-tools bind-tools tcptraceroute tcpdump 

# Install bjoern and dependencies for install
RUN apk add --no-cache --virtual .deps \
    musl-dev gcc git && \
    # Keep libev for running bjoern, libjpeg and zlib for Pillow
    apk add --no-cache libev-dev zlib-dev jpeg-dev && \
    pip install bjoern

COPY server /server
COPY --from=hilbert-assets /server/routing_project_server/static/hilbert /server/routing_project_server/static/hilbert
RUN pip install -e /server

# Default config dir
ENV SERVER_CONFIG="/server/config.py"


CMD ["python3", "/server/run.py"]
