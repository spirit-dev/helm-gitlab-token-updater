# gitlab-token-updater

## Purpose

Go application source, tests, and Docker container packaging for the GitLab token rotator binary.

## Ownership

Owns all Go application code (`app/`, `pkg/`, `main.go`), Go module files (`go.mod`, `go.sum`), tests, and Docker image specifications (`Dockerfile`, `Dockerfile.arm64`).

## Local Contracts

- Planned next feature: Move the Docker image packaging (specifically the ARM64 version) to a dedicated repository, treated and built separately from this Helm chart repo.

## Work Guidance

- Go code uses standard Go conventions; build via `go build .`.
- ARM64 build currently handled via `Dockerfile.arm64`.

## Verification

- `go test ./...`

## Child DOX Index

None.
