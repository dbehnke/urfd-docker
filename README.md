# urfd-docker

Docker build environment for the Universal Multi-protocol Digital Voice Reflector (`urfd`) and the Transcoder (`tcd`), along with the necessary vocoder libraries.

## Overview

This repository provides a multi-stage Dockerfile that compiles and packages:

1. **imbe_vocoder** (software IMBE vocoder)
2. **md380_vocoder_dynarmic** (software AMBE vocoder emulator)
3. **tcd** (Transcoder)
4. **urfd** (Universal Reflector)

The final image is based on Ubuntu 24.04 and includes all necessary runtime dependencies (`libnng`, `libcurl`, `OpenDHT`, etc.).

## Prerequisites

- Docker
- Git
- Access to the source repositories for `urfd`, `tcd`, `imbe_vocoder`, and `md380_vocoder_dynarmic` in the parent directory.

## Directory Structure

This `urfd-docker` directory is expected to be a sibling to the source directories.

```text
urfd-dev/
├── imbe_vocoder/
├── md380_vocoder_dynarmic/
├── tcd/
├── urfd/
└── urfd-docker/       <-- You are here
    ├── Dockerfile
    ├── docker-compose.yml
    ├── tcd.mk
    └── README.md
```

## Building the Image

Because the build requires context from the sibling directories (urfd, tcd, vocoders), you must run the build command from the **parent directory** (`urfd-dev`).

```bash
# From urfd-dev/
docker build -f urfd-docker/Dockerfile -t urfd-combined .
```

## Running the Stack

A `docker-compose.yml` file is provided to orchestrate `urfd` and `tcd`. It uses host networking to ensure proper UDP port handling for reflector protocols.

1. Navigate to this directory:

    ```bash
    cd urfd-docker
    ```

2. Start the services:

    ```bash
    docker-compose up
    ```

### Configuration

The `docker-compose.yml` expects configuration files to be present in a `./config` directory (relative to `docker-compose.yml`) or creates a volume. You may need to adjust the volume mappings in `docker-compose.yml` to point to your actual `config/` directory containing `urfd.ini`, `urfd.interlink`, etc.

## Details

- **Dependencies**: The build installs `libboost-all-dev`, `nlohmann-json3-dev`, `libfmt-dev`, `libnng-dev`, `libcurl4-gnutls-dev`, and `libopendht-dev`.
- **Symlink Resolution**: The Dockerfile copies the `urfd` source tree into the `tcd` build stage to resolve symlinks like `TCPacketDef.h`.
- **Stale Objects**: The build process automatically runs `make clean` to ensure that stale host object files do not interfere with the container build.
