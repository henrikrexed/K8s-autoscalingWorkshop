# 3. Cleanup

When you're done, tear everything down to free up your Codespace hours and stop sending traffic to your Dynatrace tenant.

## Tear down the kind cluster

Inside your Codespace:

```bash
kind delete cluster --name "$CLUSTER_NAME"
```

`$CLUSTER_NAME` is whatever your bootstrap derived from `$CODESPACE_NAME` — `kind get clusters` shows it.

If you only want to scale things down (you'll come back later):

```bash
# Stop the load generator first to drop traffic to zero
kubectl -n otel-demo scale deploy/load-generator --replicas=0
# Then scale everything else
kubectl -n otel-demo scale --replicas=0 \
  deploy/cart deploy/checkout deploy/frontend deploy/payment deploy/product-catalog
kubectl -n otel-demo scale --replicas=0 statefulset/postgres statefulset/valkey
```

## Stop or delete the Codespace

A Codespace stops automatically after 30 minutes of inactivity, but it keeps consuming storage. To stop it manually:

1. Go to [github.com/codespaces](https://github.com/codespaces)
2. Find your `K8s-autoscalingWorkshop` Codespace
3. Click the `...` menu → **Stop codespace** (preserves state, doesn't bill compute) **or** **Delete** (fully removes it)

## Revoke the Dynatrace tokens

Even if you stop the Codespace, the tokens you created during *Getting Started* still exist in your tenant. Revoke them when you're done:

1. Dynatrace UI → **Settings → Access tokens**
2. Find the tokens labeled with the operator/ingest scopes you created
3. **Revoke** each one

## Remove the data in Dynatrace (optional)

The OneAgent + ActiveGate data your tenant collected will age out naturally according to your tenant's retention. If you want to clear it sooner:

1. **Settings → Monitored entities** → filter to the Kubernetes cluster name (your Codespace name) → delete entities
2. **Settings → Hosts** → mark any reported hosts as decommissioned
3. **Logs** + **Metrics** age out per your retention policy — no manual purge needed

The pre-provisioned **notebook** stays on the trial tenant for the next workshop session. You can delete the imported **workflow** from the Workflows app if you no longer need it.

## Delete the fork (optional)

If this was a one-off and you don't want the fork sitting in your account:

1. Open your fork on GitHub
2. **Settings → General**, scroll to the bottom
3. **Danger Zone → Delete this repository**

Done!
