FROM goreleaser/goreleaser:v2.18.2@sha256:7077423cf5ef643ff56a34b58f93c1364e927e5c3dfa470eeabc44cab1a9c72b AS builder
WORKDIR /build
COPY . .
RUN goreleaser build --clean --single-target

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
RUN apk --no-cache add ca-certificates
COPY --from=builder /build/dist/gitlab-token-updater_linux_amd64_v1/gitlab-token-updater /usr/bin/gitlab-token-updater
ENTRYPOINT ["gitlab-token-updater"]
CMD ["--help"]