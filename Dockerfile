FROM golang:1.21 AS build

ARG SM_VERSION
ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_DIR=${GOPATH}/src/github.com/JustaPenguin/assetto-server-manager
ENV GO111MODULE=on

RUN curl -sL https://deb.nodesource.com/setup_20.x | bash -
RUN apt-get update && apt-get install -y build-essential libssl-dev curl nodejs tofrodos dos2unix zip

ADD . ${BUILD_DIR}
WORKDIR ${BUILD_DIR}
RUN rm -rf cmd/server-manager/typescript/node_modules

# Install esc tool for embedding assets
RUN go get -v github.com/mjibson/esc && go install github.com/mjibson/esc

# Build TypeScript/JavaScript assets first
RUN cd cmd/server-manager/typescript && npm install && npx gulp build

# Generate embedded Go files (requires esc to be installed)
RUN go generate ./...

# Build the binary
RUN cd cmd/server-manager && \
    mkdir -p build/linux && \
    cp config.example.yml build/linux/config.yml && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -a -installsuffix cgo \
    -ldflags="-s -w -X github.com/JustaPenguin/assetto-server-manager.BuildVersion=${SM_VERSION}" \
    -o build/linux/server-manager

RUN mv cmd/server-manager/build/linux/server-manager /usr/bin/

FROM ubuntu:22.04 AS run
LABEL maintainer="psalkowski"
LABEL org.opencontainers.image.source="https://github.com/psalkowski/assetto-server-manager"

ENV DEBIAN_FRONTEND=noninteractive

ENV SERVER_USER=assetto
ENV SERVER_MANAGER_DIR=/home/${SERVER_USER}/server-manager/
ENV SERVER_INSTALL_DIR=${SERVER_MANAGER_DIR}/assetto
ENV LANG=C.UTF-8

ENV STEAMCMD_URL="http://media.steampowered.com/installer/steamcmd_linux.tar.gz"
ENV STEAMROOT=/opt/steamcmd

# Add i386 architecture for SteamCMD (32-bit)
RUN dpkg --add-architecture i386
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    lib32gcc-s1 \
    lib32stdc++6 \
    libsdl2-2.0-0:i386 \
    && rm -rf /var/lib/apt/lists/*
# Install SteamCMD
RUN mkdir -p ${STEAMROOT}
WORKDIR ${STEAMROOT}
RUN curl -s ${STEAMCMD_URL} | tar -xz
RUN ${STEAMROOT}/steamcmd.sh +quit || true
ENV PATH="${STEAMROOT}:${PATH}"

RUN useradd -ms /bin/bash ${SERVER_USER}

RUN mkdir -p ${SERVER_MANAGER_DIR} && mkdir ${SERVER_INSTALL_DIR}

RUN chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_MANAGER_DIR}
RUN chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_INSTALL_DIR}

COPY --from=build /usr/bin/server-manager /usr/bin/

USER ${SERVER_USER}
WORKDIR ${SERVER_MANAGER_DIR}

# recommend volume mounting the entire assetto corsa directory
VOLUME ["${SERVER_INSTALL_DIR}"]

# Expose ports
# 8772 - Web UI
# 9600 - AC Server UDP
# 9601 - AC Server TCP
# 8081 - AC Server HTTP
EXPOSE 8772 9600/udp 9601/tcp 8081/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8772/ || exit 1

ENTRYPOINT ["server-manager"]
