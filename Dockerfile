# Base stage for build dependencies
FROM ubuntu:24.04 AS base-dev
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libnng-dev \
    libcurl4-gnutls-dev \
    libopendht-dev \
    libboost-all-dev \
    nlohmann-json3-dev \
    libfmt-dev \
    libopus-dev \
    libogg-dev \
    unzip \
    python3 \
    golang-go \
    wget \
    curl \
    xxd \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Stage: source-fetcher
FROM alpine/git AS source-fetcher
ARG DASHBOARD_COMMIT
WORKDIR /src
RUN git clone https://github.com/dbehnke/urfd-nng-dashboard.git . && \
    git checkout ${DASHBOARD_COMMIT}

# Stage: vocoders
# Assumes build context is urfd-dev (parent directory)
FROM base-dev AS vocoders
WORKDIR /build

# Build imbe_vocoder
# Copying from context ../imbe_vocoder
COPY imbe_vocoder /build/imbe_vocoder
WORKDIR /build/imbe_vocoder
RUN make clean && make && (make install || true) \
    && cp libimbe_vocoder.a /usr/local/lib/ \
    && cp *.h /usr/local/include/

# Build md380_vocoder_dynarmic
COPY md380_vocoder_dynarmic /build/md380_vocoder_dynarmic
WORKDIR /build/md380_vocoder_dynarmic
# Clean stale build artifacts from host
RUN rm -rf build && mkdir build
WORKDIR /build/md380_vocoder_dynarmic/build
# History shows cmake usage and potentially makelib.sh
RUN cmake .. && make && bash -x ../makelib.sh \
    && cp libmd380_vocoder.a /usr/local/lib/ \
    && cp ../md380_vocoder.h /usr/local/include/

# Stage: tcd-builder
FROM base-dev AS tcd-builder
WORKDIR /build/tcd

# Copy tcd source
COPY tcd /build/tcd

# Copy configuration to root as expected by Makefile
COPY tcd.mk /build/tcd/tcd.mk

# Copy urfd source to resolve symlinks (e.g. TCPacketDef.h)
COPY urfd /build/urfd

# Copy vocoder artifacts from /usr/local of vocoders stage
COPY --from=vocoders /usr/local/lib/libimbe_vocoder.a /usr/local/lib/
COPY --from=vocoders /usr/local/include/*.h /usr/local/include/
# imbe_vocoder might install more headers or in a subdir, but history showed basic install. 
# Check history for imbe install details? Line 87 just says 'make install'.
# Assuming standard locations.

COPY --from=vocoders /usr/local/lib/libmd380_vocoder.a /usr/local/lib/
COPY --from=vocoders /usr/local/include/md380_vocoder.h /usr/local/include/


WORKDIR /build/tcd
RUN sed -i 's/-lmd380_vocoder/-lmd380_vocoder -lfmt/g' Makefile && make clean && make swmodes=true

# Stage: urfd-builder
FROM base-dev AS urfd-builder
WORKDIR /build/urfd

COPY urfd /build/urfd
WORKDIR /build/urfd/reflector
COPY urfd.mk /build/urfd/reflector/urfd.mk
RUN make clean && make

# Stage: frontend-builder
FROM oven/bun:1 AS frontend-builder
# Install go-task
RUN apt-get update && apt-get install -y curl git && rm -rf /var/lib/apt/lists/* \
    && sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

WORKDIR /app
COPY --from=source-fetcher /src/web ./web
COPY --from=source-fetcher /src/Taskfile.yml .
COPY --from=source-fetcher /src/.git ./.git

RUN task install-frontend && task build-frontend

# Stage: dashboard-builder
FROM base-dev AS dashboard-builder
WORKDIR /build/urfd-nng-dashboard
COPY --from=source-fetcher /src /build/urfd-nng-dashboard
# We copied the whole src, does it include .git?
# git clone in source-fetcher creates .git.
# COPY --from=source-fetcher /src ...
# Docker COPY usually skips .git if excluded, but here we are copying from another stage directory.
# Wait, COPY command does NOT automatically skip .git unless .dockerignore says so.
# But source-fetcher has .git inside /src.
# COPY --from=source-fetcher /src /build/urfd-nng-dashboard
# This should copy everything, including .git.
# So dashboard-builder might already have it?
# Let's verify why dashboard-builder wasn't failing (or if it reached it).
# The failure was in frontend-builder.
# In frontend-builder, we explicitly copied only specific files.
# In dashboard-builder, we copy `/src`.
# I will NOT touch dashboard-builder if it seemingly copies everything.
# I will only fix frontend-builder.
# However, to be safe and explicit, I will verify if I need to do anything there.
# I'll stick to fixing frontend-builder first.

# Copy built frontend assets (Taskfile sync-assets expects web/dist or handles it? Check Taskfile)
# Taskfile 'sync-assets' copies web/dist/* to internal/assets/dist/
# In frontend-builder, we built in /app/urfd-nng-dashboard/web/dist
# We need to copy that to /build/urfd-nng-dashboard/web/dist first, then run sync-assets?
# Or just copy directly to internal/assets/dist?
# Taskfile 'build-backend' depends on 'sync-assets'.
# 'sync-assets' does: cp -r web/dist/* internal/assets/dist/
# So we need web/dist to exist.

COPY --from=frontend-builder /app/web/dist ./web/dist
RUN task build-backend
# Stage: final
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libnng1 \
    libcurl3t64-gnutls \
    libopendht-dev \
    libopus0 \
    libogg0 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/bin

# Copy binaries
COPY --from=tcd-builder /build/tcd/tcd .
COPY --from=urfd-builder /build/urfd/reflector/urfd .
COPY --from=urfd-builder /build/urfd/reflector/inicheck .
COPY --from=urfd-builder /build/urfd/reflector/dbutil .
COPY --from=urfd-builder /build/urfd/radmin .
COPY --from=dashboard-builder /build/urfd-nng-dashboard/urfd-dashboard ./dashboard

# Ensure they are executable
RUN chmod +x tcd urfd inicheck dbutil radmin dashboard

# No entrypoint, default CMD
CMD ["/bin/bash"]
