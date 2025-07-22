# syntax=docker/dockerfile:1.4
FROM nixos/nix:2.30.1-arm64 AS nix-build

WORKDIR /build
COPY flake.nix flake.lock ./
COPY hosts ./hosts/

# Build specified Pi image
ARG PI_HOST=pi5
RUN nix build .#installerConfigurations.${PI_HOST} \
    --extra-experimental-features "nix-command flakes" \
    --accept-flake-config \
    --out-link /tmp/result

# Copy the actual image file, not the symlink
RUN mkdir -p /output && \
    cp -L /tmp/result/sd-image/*.img.zst /output/

FROM scratch
COPY --from=nix-build /output/*.img.zst /
