# examples/k8s

Raw Kubernetes manifests. Apply in order, edit placeholders marked `<CHANGE_ME>`.

For Helm-based deployment (easier for ongoing ops), use `examples/helm/bugsink/` instead.

## Apply order

```bash
kubectl create namespace bugsink

# 1. Secrets (either direct or via ExternalSecret)
kubectl apply -f external-secret.yaml                    # if using External Secrets Operator
# OR
# kubectl create secret generic bugsink-secret -n bugsink \
#   --from-literal=SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))') \
#   --from-literal=DB_PASSWORD='<your-db-password>'

# 2. Service account (needed for IRSA on EKS or Workload Identity on GKE)
kubectl apply -f service-account.yaml

# 3. StatefulSet + Service
kubectl apply -f statefulset.yaml
kubectl apply -f service.yaml

# 4. Ingress (pick one)
kubectl apply -f gke-ingress.yaml   # for GKE
# OR
kubectl apply -f eks-alb-ingress.yaml   # for EKS

# 5. Source-map upload Job (after first successful FE deploy)
# kubectl apply -f sourcemap-upload-job.yaml   # usually via Helm post-install hook instead
```

## What's in this folder

| File | Purpose |
|------|---------|
| `statefulset.yaml` | BugSink pod + Cloud SQL proxy sidecar (GCP) or direct RDS (AWS) |
| `service.yaml` | ClusterIP service — carries the `cloud.google.com/neg` annotation |
| `service-account.yaml` | K8s SA annotated for Workload Identity / IRSA |
| `external-secret.yaml` | External Secrets Operator ExternalSecret for SECRET_KEY + DB_PASSWORD |
| `gke-ingress.yaml` | GKE Ingress + ManagedCertificate + BackendConfig → Cloud Armor |
| `eks-alb-ingress.yaml` | AWS ALB Ingress + WAF attachment |
| `sourcemap-upload-job.yaml` | Job to upload FE source maps (Helm-hook-compatible) |
| `networkpolicy.yaml` | Optional egress restriction |

## Cloud-agnostic vs cloud-specific

`statefulset.yaml`, `service.yaml`, `service-account.yaml`, `external-secret.yaml`, `sourcemap-upload-job.yaml` are cloud-agnostic. Minor value changes per cloud.

`gke-ingress.yaml` and `eks-alb-ingress.yaml` are obviously cloud-specific.

`networkpolicy.yaml` works everywhere — requires your CNI to support NetworkPolicy (Calico, Cilium, AWS VPC CNI with `ENABLE_POD_ENI`, etc.).
