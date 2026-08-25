# Kubernetes deployment

This guide is a baseline for cluster administrators. Kubernetes storage classes, node seccomp installation, ingress policy, and secret management differ between clusters; review the manifests before applying them.

## Prerequisites

- A default `ReadWriteOnce` storage class, or explicit storage classes added to the claims below.
- The exported `docker/seccomp_profile.json` installed as `bursula.json` below the kubelet seccomp profile root on every eligible node. The example therefore uses `Localhost` seccomp instead of disabling Chromium's sandbox.
- `kubectl` access that can create a namespace, PVCs, Secrets, Deployments, Services, and CronJobs.

Create the namespace and the exactly eight-character internal VNC password:

```bash
kubectl create namespace bursula
kubectl -n bursula create secret generic bursula-novnc \
  --from-literal=novnc-password="$(openssl rand -hex 4)"
```

Use your cluster's external secret provider for production target credentials. Never store credentials directly in a manifest.

## Persistent storage

Save this as `storage.yaml`, adjust sizes and storage classes, then apply it:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bursula-state
  namespace: bursula
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bursula-invoices
  namespace: bursula
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 20Gi
```

```bash
kubectl apply -f storage.yaml
```

The state claim contains the license, authenticated browser profiles, catalog, and run state. Back it up only while no setup or run Pod is active, and protect the backup like a credential.

## Temporary web setup

Save this as `setup.yaml`. Change `localhostProfile` if the profile has a different path relative to your kubelet seccomp root.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bursula-setup
  namespace: bursula
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bursula-setup
  template:
    metadata:
      labels:
        app: bursula-setup
    spec:
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: Localhost
          localhostProfile: bursula.json
      containers:
        - name: bursula
          image: ghcr.io/bursula/bursula:0.3.3
          args: [setup, web]
          env:
            - name: BURSULA_ENABLE_NOVNC
              value: "1"
            - name: BURSULA_ENABLE_SETUP_WEB
              value: "1"
            - name: BURSULA_VNC_PASSWORD_FILE
              value: /run/secrets/novnc-password
          ports:
            - name: setup
              containerPort: 6080
          resources:
            requests:
              memory: 1Gi
            limits:
              memory: 2Gi
          volumeMounts:
            - name: state
              mountPath: /home/node/.bursula
            - name: invoices
              mountPath: /invoices
            - name: novnc-password
              mountPath: /run/secrets/novnc-password
              subPath: novnc-password
              readOnly: true
            - name: shared-memory
              mountPath: /dev/shm
      volumes:
        - name: state
          persistentVolumeClaim:
            claimName: bursula-state
        - name: invoices
          persistentVolumeClaim:
            claimName: bursula-invoices
        - name: novnc-password
          secret:
            secretName: bursula-novnc
            defaultMode: 0400
        - name: shared-memory
          emptyDir:
            medium: Memory
            sizeLimit: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: bursula-setup
  namespace: bursula
spec:
  type: ClusterIP
  selector:
    app: bursula-setup
  ports:
    - name: setup
      port: 6080
      targetPort: setup
```

Apply it, wait for the Pod, and keep the unencrypted setup endpoint private by using `kubectl port-forward`:

```bash
kubectl apply -f setup.yaml
kubectl -n bursula rollout status deployment/bursula-setup
kubectl -n bursula logs -f deployment/bursula-setup
kubectl -n bursula port-forward service/bursula-setup 6080:6080
```

Open the one-time `http://127.0.0.1:6080/#token=...` URL printed in the logs, upload the license, and complete the browser login. Do not expose port 6080 through a public LoadBalancer or unprotected Ingress. When setup is complete, stop the setup Pod before scheduling runs:

```bash
kubectl -n bursula scale deployment/bursula-setup --replicas=0
```

## Scheduled runs

Save this as `cronjob.yaml`, choose the required schedule, and reuse the same seccomp profile and claims. `concurrencyPolicy: Forbid` prevents overlapping runs.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: bursula
  namespace: bursula
spec:
  schedule: "0 6 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          securityContext:
            fsGroup: 1000
            seccompProfile:
              type: Localhost
              localhostProfile: bursula.json
          containers:
            - name: bursula
              image: ghcr.io/bursula/bursula:0.3.3
              args: [run, --all]
              resources:
                requests:
                  memory: 1Gi
                limits:
                  memory: 2Gi
              volumeMounts:
                - name: state
                  mountPath: /home/node/.bursula
                - name: invoices
                  mountPath: /invoices
                - name: shared-memory
                  mountPath: /dev/shm
          volumes:
            - name: state
              persistentVolumeClaim:
                claimName: bursula-state
            - name: invoices
              persistentVolumeClaim:
                claimName: bursula-invoices
            - name: shared-memory
              emptyDir:
                medium: Memory
                sizeLimit: 1Gi
```

```bash
kubectl apply -f cronjob.yaml
kubectl -n bursula create job --from=cronjob/bursula bursula-manual
kubectl -n bursula logs -f job/bursula-manual
```

An exit code of `2` requires reauthentication. Scale the CronJob setup down or suspend it before scaling `bursula-setup` back to one replica, then repeat the private port-forward flow.
