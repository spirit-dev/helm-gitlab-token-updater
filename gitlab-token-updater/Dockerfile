FROM goreleaser/goreleaser:v2.18.3@sha256:b61a4eedf5e3b1d283792dade34ee0f8c6cce3e6f1f65851d3b397b8f8a75b6d AS builder
WORKDIR /build
COPY . .
RUN goreleaser build --clean --single-target

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
RUN apk --no-cache add ca-certificates
COPY --from=builder /build/dist/gitlab-token-updater_linux_amd64_v1/gitlab-token-updater /usr/bin/gitlab-token-updater
ENTRYPOINT ["gitlab-token-updater"]
CMD ["--help"]