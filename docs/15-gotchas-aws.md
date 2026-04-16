# 15 — Gotchas (AWS-Specific)

AWS-only issues layered on top of [`13-gotchas.md`](13-gotchas.md).

---

## 1. AWS Load Balancer Controller must be installed BEFORE you create Ingress resources

If you `helm install` BugSink with an ALB Ingress before the ALB Controller is running, the Ingress sits in `Pending` with no `ADDRESS` forever. No error message unless you check the Controller logs.

**Fix:** install ALB Controller first, verify it's Running:

```bash
kubectl get deploy -n kube-system aws-load-balancer-controller
```

If not installed: [official install guide](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/).

---

## 2. `target-type: ip` vs `instance`

ALB Ingress has two target-type modes:

- `instance` — ALB sends to the node, kube-proxy routes to the pod. Extra hop. Limits to one Service port per target.
- `ip` — ALB sends directly to the pod IP. Requires AWS VPC CNI (default on EKS). Production-standard.

**Fix:** use `target-type: ip`. Make sure your VPC subnets are tagged so the ALB Controller can find them:

```
kubernetes.io/role/elb = 1       # for public ALB
kubernetes.io/role/internal-elb = 1  # for internal ALB
```

---

## 3. IRSA token audience mismatch

If the pod's IAM role trust policy's `aud` doesn't match what the EKS OIDC provider returns, `assume-role-with-web-identity` fails silently — the pod gets no credentials, Secret Manager calls fail with `UnrecognizedClientException`.

**Fix:** the trust policy must include:

```json
"Condition": {
  "StringEquals": {
    "oidc.eks.REGION.amazonaws.com/id/XXXXX:sub": "system:serviceaccount:bugsink:bugsink",
    "oidc.eks.REGION.amazonaws.com/id/XXXXX:aud": "sts.amazonaws.com"
  }
}
```

`aud` must be `sts.amazonaws.com`, not anything else.

---

## 4. RDS security group not open to EKS pods

Pod → RDS TCP 5432 fails because the RDS security group doesn't allow inbound from the EKS node security group (or the pod CIDR if using Fargate).

**Fix:**

```bash
# Get the EKS node SG
EKS_NODE_SG=$(aws eks describe-cluster --name my-cluster \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Allow RDS SG to accept 5432 from EKS node SG
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp --port 5432 \
  --source-group $EKS_NODE_SG
```

---

## 5. ACM certificate must be in the same region as the ALB

ACM certs are regional. If you request a cert in `us-east-1` but your EKS + ALB are in `us-west-2`, the cert won't attach.

**Exception:** CloudFront distributions can use `us-east-1` certs from any CloudFront edge. But ALBs cannot.

**Fix:** request the cert in the same region as your EKS cluster.

---

## 6. WAFv2 scope: REGIONAL vs CLOUDFRONT

WAFv2 has two scopes:
- `REGIONAL` — for ALB, API Gateway, AppSync
- `CLOUDFRONT` — for CloudFront distributions only

If you create a WAFv2 WebACL in `CLOUDFRONT` scope, you can't attach it to an ALB.

**Fix:** always use `REGIONAL` scope for BugSink's ALB.

---

## 7. ALB healthcheck path returning 302 marks target unhealthy

Default ALB healthcheck expects 200-399, but `/` on BugSink returns 302 (redirect to login). Some teams tighten the matcher to 200-only and end up with unhealthy targets.

**Fix:** set healthcheck path to `/accounts/login/` (returns 200) via annotation:

```yaml
alb.ingress.kubernetes.io/healthcheck-path: /accounts/login/
alb.ingress.kubernetes.io/success-codes: "200"
```

---

## 8. ALB target group deregistration delay blocks rolling updates

Default deregistration delay is 300s. On pod rollouts, this makes rolling updates feel stuck — the old pod is draining, the new pod is healthy, but kubectl rollout status hangs.

**Fix:** lower the delay for BugSink (no long-running connections):

```yaml
alb.ingress.kubernetes.io/target-group-attributes: "deregistration_delay.timeout_seconds=30"
```

---

## 9. NAT Gateway EIP rotates if you recreate the NAT GW

If someone `terraform destroy`s and recreates the NAT GW, the EIP changes. Your WAF IPSet still references the old EIP — cluster loses access to allowlisted resources.

**Fix:** declare the EIP as a separate `aws_eip` resource and reference it in both the NAT GW config AND the WAF IPSet. Then destroy/recreate of the NAT GW doesn't affect the EIP.

See `examples/terraform/aws/nat-eip.tf`.

---

## 10. CloudWatch Logs retention defaults to "Never Expire"

BugSink logs to stdout → container logs → CloudWatch Logs. Default retention is forever. Over time, this adds up to $$$.

**Fix:** set retention explicitly on the log group:

```bash
aws logs put-retention-policy \
  --log-group-name /aws/eks/my-cluster/cluster \
  --retention-in-days 30
```

---

## 11. Secrets Manager rotation can break your pod

If you enable automatic rotation on `bugsink/db-password` in Secrets Manager without updating the DB password too, the pod's next read fetches the new password but the DB still expects the old one → auth fails → pod crashes.

**Fix:** if you rotate, use Secrets Manager's RDS rotation Lambda that rotates both sides atomically. Or disable rotation and rotate manually with a coordinated restart.

---

## 12. `aws` CLI config profile confusion

Multiple AWS accounts (dev + prod) is like GCP's multiple configurations. Running the wrong command against the wrong account is easy.

**Fix:** always use named profiles:

```bash
aws --profile prod rds describe-db-instances
```

Or set `AWS_PROFILE` env var per shell session. Scripts should echo the active profile before destructive ops.

---

## 13. EKS pod-to-pod via `Service` works; via Service IP sometimes doesn't (Fargate)

On Fargate, direct Service IP routing (`10.100.x.x`) sometimes fails while DNS-based routing works. Always prefer the SVC DNS name (`bugsink-svc.bugsink.svc.cluster.local`) in `SENTRY_DSN` — more portable across EKS and Fargate.

---

## 14. ELB pre-warming

If you expect a traffic spike (e.g. launching a new app that starts reporting errors), AWS recommends ALB pre-warming via a support ticket. For BugSink, this is usually unnecessary — error traffic is bursty but low-volume. But if you have 10k+ SDK clients coming online simultaneously, ALB scale-up might lag.

---

## 15. `aws-load-balancer-controller` and IngressClass

AWS Load Balancer Controller watches Ingress resources with `kubernetes.io/ingress.class: alb` (legacy) or an IngressClass resource with `spec.controller: ingress.k8s.aws/alb`. The legacy annotation is deprecated — newer controller versions prefer the IngressClass.

**Fix:** use the IngressClass resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
spec:
  controller: ingress.k8s.aws/alb
```

Then reference `spec.ingressClassName: alb` in your Ingress.
