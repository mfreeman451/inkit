# Kubernetes Deployment

This directory contains the Kustomize base and Argo CD Application for deploying the Visual Assistant to `inkit.carverauto.dev`.

## Image

The Deployment uses:

```text
ghcr.io/mfreeman451/inkit:latest
```

The release workflow publishes that tag after a GitHub release/tag build.

## Runtime

- Namespace: `inkit`
- Public host: `inkit.carverauto.dev`
- Shared Envoy Gateway: `carverauto-web/carverauto-web-gateway`
- Shared Gateway LoadBalancer IP: `23.138.124.29`
- TLS issuer: `carverauto-issuer`
- TLS secret: `carverauto-web/inkit-tls`
- Persistent data: `inkit-data` PVC mounted at `/data`
- SQLite path: `/data/inkit.db`
- Upload path: `/data/uploads`
- Runtime secret: `inkit-runtime`, committed as a SealedSecret

The app does not allocate a dedicated MetalLB address. It reuses the existing
`carverauto-web-gateway` LoadBalancer IP and adds a hostname-specific
`https-inkit` listener that terminates with a dedicated `inkit-tls` certificate.
That certificate contains only `inkit.carverauto.dev`; it does not take
ownership of the existing `carverauto.dev` or `www.carverauto.dev` certificate.
Traffic routes from the `carverauto-web` namespace to the `inkit` service
through a `ReferenceGrant`.

The `inkit-tls` certificate and `HTTPRoute` live in `carverauto-web` because
Gateway listener TLS secrets must be local to the Gateway namespace. The app
workload, PVC, runtime secret, service, and network policies remain isolated in
the `inkit` namespace.

## Argo CD

Apply the Argo CD application from a machine with cluster access:

```bash
kubectl apply -f k8s/argocd-application.yaml
```

Argo CD will sync `k8s/base` from `main`.
