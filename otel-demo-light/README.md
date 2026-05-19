# otel-demo-light deployment

The application used in this demo is the lightweight version of the
OpenTelemetry Astronomy Shop maintained at:

    https://github.com/henrikrexed/opentelemetry-demo-light

It is a smaller fork of the upstream `open-telemetry/opentelemetry-demo`
designed to fit in resource-constrained environments such as a kind
cluster running inside a GitHub Codespace.

## How it is deployed

`deployment.sh` clones the repository at runtime and looks for one of the
following deployment artifacts (in this order):

1. `kubernetes/opentelemetry-demo.yaml`
2. `kubernetes/manifest.yaml`
3. `kustomization.yaml` at the repo root
4. `kustomize/base/kustomization.yaml`

Whichever is found first is applied to the `otel-demo` namespace.

The OTLP endpoint of the demo's collector / SDKs is overridden so that
all telemetry is sent to the cluster-local OpenTelemetry Collector at
`otel-collector.otel-collector.svc.cluster.local:4317`, which forwards
to Dynatrace.

## Why pull at runtime instead of vendoring the manifest

The upstream demo manifest changes frequently and is large (>2k lines).
Pulling at runtime keeps this repository small and always in sync with
the demo-light's latest images.
