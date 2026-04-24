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
- Persistent data: `inkit-data` PVC mounted at `/data`
- SQLite path: `/data/inkit.db`
- Upload path: `/data/uploads`
- Runtime secret: `inkit-runtime`, committed as a SealedSecret

The app does not allocate a dedicated MetalLB address. It reuses the existing
`carverauto-web-gateway` listener and routes `inkit.carverauto.dev` from the
`carverauto-web` namespace to the `inkit` service through a `ReferenceGrant`.
The `carverauto-web-tls` certificate is extended to include
`inkit.carverauto.dev` so the existing HTTPS listener can terminate TLS for the
new hostname.

## Argo CD

Apply the Argo CD application from a machine with cluster access:

```bash
kubectl apply -f k8s/argocd-application.yaml
```

Argo CD will sync `k8s/base` from `main`.
