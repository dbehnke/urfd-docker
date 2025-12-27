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
    unzip \
    python3 \
    golang-go \
    wget \
    xxd \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

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
RUN sed -i 's/-lmd380_vocoder/-lmd380_vocoder -lfmt/g' Makefile && make clean && make

# Stage: urfd-builder
FROM base-dev AS urfd-builder
WORKDIR /build/urfd

COPY urfd /build/urfd
WORKDIR /build/urfd/reflector
COPY urfd.mk /build/urfd/reflector/urfd.mk
RUN make clean && make

# Stage: dashboard-builder
FROM base-dev AS dashboard-builder
WORKDIR /build/urfd-nng-dashboard
COPY urfd-nng-dashboard /build/urfd-nng-dashboard
WORKDIR /build/urfd-nng-dashboard
RUN go build -o dashboard cmd/dashboard/main.go
# Stage: final
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libnng1 \
    libcurl3t64-gnutls \
    libopendht-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/bin

# Copy binaries
COPY --from=tcd-builder /build/tcd/tcd .
COPY --from=urfd-builder /build/urfd/reflector/urfd .
COPY --from=urfd-builder /build/urfd/reflector/inicheck .
COPY --from=urfd-builder /build/urfd/reflector/dbutil .
COPY --from=urfd-builder /build/urfd/radmin .
COPY --from=dashboard-builder /build/urfd-nng-dashboard/dashboard .

# Ensure they are executable
RUN chmod +x tcd urfd inicheck dbutil radmin dashboard

# No entrypoint, default CMD
CMD ["/bin/bash"]
