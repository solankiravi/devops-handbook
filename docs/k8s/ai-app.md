# How the ai-app deployment behaves

This page explains the Kubernetes objects in `deployment/k8s/ai_app` and what each one does at runtime. The cluster is a local [kind](../kind/setup.md) cluster. The app is three tiers: a React frontend, a FastAPI backend, and Postgres. Each tier is its own Pod. A fourth Deployment, `docs`, serves this handbook.

Read it next to the manifests. Every name below is a name in those files.

## What is running

Kubernetes does not run the YAML. `kubectl apply -k deployment/k8s/ai_app` sends the objects to the API server. Controllers then create the Pods, attach storage, and publish network addresses.

After a successful apply, the `ai-app` namespace holds:

| Object | Name | Job |
| --- | --- | --- |
| Namespace | `ai-app` | Boundary for every other object |
| Secret | `postgres` | Username, password, database name, and `DATABASE_URL` |
| PersistentVolumeClaim | `postgres-data` | Request for 1Gi of disk |
| PersistentVolume | created by the cluster | The actual disk bound to that claim |
| Deployment | `postgres`, `backend`, `frontend`, `docs` | Desired state for one Pod each |
| ReplicaSet | owned by each Deployment | Keeps that one Pod running |
| Pod | one per Deployment | The container that does the work |
| Service | `postgres`, `backend`, `frontend`, `docs` | Stable address in front of the current Pod |
| EndpointSlice | one per Service | Pod IPs that are ready to receive traffic |

`kustomization.yaml` is not a cluster object. It is a build list for `kubectl apply -k`. It tells kubectl to send `namespace.yaml`, then `postgres.yaml`, `backend.yaml`, `frontend.yaml`, and `docs.yaml`.

## Request path

Two different networks are involved. The browser runs on your machine. The Pods run inside the kind node.

```text
browser on your machine
  |  http://127.0.0.1:5173/
  |  kubectl port-forward svc/frontend 5173:80
  v
Service/frontend :80  -->  frontend Pod :80  (nginx serves the built React app)

browser on your machine
  |  http://127.0.0.1:8000/     (hardcoded in the React bundle)
  |  kubectl port-forward svc/backend 8000:8000
  v
Service/backend :8000  -->  backend Pod :8000  (uvicorn returns {"message":"Hello World"})
```

The React code in `ai_app/frontend/app/src/App.tsx` calls `http://127.0.0.1:8000/`. That address is the port-forward on your machine. The page does not call the in-cluster name `backend`.

The backend container is given this environment variable:

```text
DATABASE_URL=postgresql://app:app@postgres:5432/app
```

`postgres` in that URL is the Service name. From a Pod inside `ai-app`, CoreDNS resolves `postgres` to the Service ClusterIP, and the Service forwards port 5432 to the Postgres Pod. The FastAPI process currently does not open that URL. The variable is present so the wiring can be inspected; the handler in `ai_app/backend/app/src/app/main.py` returns a fixed JSON object and does not connect to the database.

CORS allows the page only when the browser origin is `http://localhost:5173` or `http://127.0.0.1:5173`. The frontend port-forward uses local port 5173 for that reason. A different local port would load the HTML and then fail the API call in the browser.

## Apply, build, and load

Images are built on the host from `docker/ai_app/Dockerfile`, one `--target` per tier:

```bash
docker build -f docker/ai_app/Dockerfile --target backend  -t ai-app-backend:latest .
docker build -f docker/ai_app/Dockerfile --target frontend -t ai-app-frontend:latest .
docker build -f docker/ai_app/Dockerfile --target postgres -t ai-app-postgres:latest .
kind load docker-image ai-app-backend:latest ai-app-frontend:latest ai-app-postgres:latest
docker build -f docker/docs/Dockerfile -t ai-app-docs:latest .
kind load docker-image ai-app-docs:latest
kubectl apply -k deployment/k8s/ai_app
```

`kind load` copies the images into the kind node's containerd. The manifests set `imagePullPolicy: IfNotPresent`, so the kubelet uses that local copy and does not try Docker Hub. If the image was never loaded, the Pod stays in `ImagePullBackOff` because `ai-app-backend:latest` is not a public image.

`latest` plus `IfNotPresent` has a consequence: after you rebuild an image, loading it again is not enough. The node already has a image named `ai-app-backend:latest`, so the kubelet keeps the old one. Delete the Pod, or change the tag, to start a container from the new build. The Deployment then creates a replacement Pod.

```bash
kubectl -n ai-app delete pod -l app=backend
```

## Namespace

`namespace.yaml` creates `ai-app`.

A namespace is a folder in the API. Names only have to be unique inside it, so a Service named `backend` here does not collide with a Service named `backend` in `default`. Every object in the other files sets `namespace: ai-app`. `kubectl` commands for this app need `-n ai-app`, or they look in `default` and report that nothing is there.

Deleting the namespace deletes the Deployments, Pods, Services, Secret, and claim inside it.

## Secret

The first document in `postgres.yaml` is a Secret named `postgres`.

`stringData` is plain text in the manifest. On apply, the API server stores those values under `data` as base64. Base64 is encoding, not encryption. Anyone who can `kubectl get secret` in this namespace can read the password.

Keys:

| Key | Value in this repo | Who reads it |
| --- | --- | --- |
| `POSTGRES_USER` | `app` | Postgres entrypoint, via `env` on the postgres container |
| `POSTGRES_PASSWORD` | `app` | Postgres entrypoint |
| `POSTGRES_DB` | `app` | Postgres entrypoint, creates that database on first start |
| `DATABASE_URL` | `postgresql://app:app@postgres:5432/app` | Backend container, via `env` |

The Pods do not receive the whole Secret as a file. Each container asks for specific keys with `valueFrom.secretKeyRef`. That copies the decoded value into an environment variable when the container starts. Changing the Secret does not change the variable in an already running container. The Pod has to be recreated.

This password is a local learning value committed in the manifest. A real cluster would not store a production password in git.

## Persistent storage

Postgres is the only tier with disk.

### PersistentVolumeClaim `postgres-data`

A claim is a request: 1Gi, `ReadWriteOnce`. The manifest does not name a StorageClass, so the cluster default is used. On the kind cluster from `docs/kind/setup.md`, that class is `standard` (`rancher.io/local-path`) and its binding mode is `WaitForFirstConsumer`.

`WaitForFirstConsumer` means the claim stays `Pending` until a Pod that mounts it has been scheduled. The provisioner then creates a PersistentVolume on that node and binds the claim. `kubectl get pvc -n ai-app` shows `Bound` once that has happened.

`ReadWriteOnce` means one node can mount the volume read-write. This Deployment runs a single Postgres Pod, which matches that mode. Raising `replicas` above 1 would ask two Pods to mount the same claim. On one kind node that still fails for a second Postgres process, and on multiple nodes `ReadWriteOnce` cannot follow both Pods.

### Volume and volumeMount

Inside the Pod spec:

- `volumes[].name: data` attaches claim `postgres-data` under the name `data`.
- `volumeMounts` on the container mounts that volume at `/var/lib/postgresql`.

The official Postgres 18 image keeps its files under that directory, in a versioned subdirectory. The mount has to be `/var/lib/postgresql`. Mounting only `/var/lib/postgresql/data` is the older layout and does not match this image.

The volume outlives the Pod. Deleting the postgres Pod deletes the container writable layer and keeps the claim. The new Pod mounts the same files, so the database survives a restart. Deleting the PersistentVolumeClaim, or the namespace, deletes the data. The kind StorageClass reclaim policy is `Delete`.

The official entrypoint initializes the database only when the data directory is empty. On that first start it reads `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`. Later restarts ignore those variables and open the existing files. Changing the Secret password after the first start does not rotate the password inside Postgres.

## Deployment, ReplicaSet, and Pod

Each tier has a Deployment with `replicas: 1`. A Deployment does not run the process itself. It stores the desired Pod template and creates a ReplicaSet. The ReplicaSet is responsible for the count.

You can see the ownership chain with:

```bash
kubectl -n ai-app get deploy,rs,pod -o wide
```

A Pod name looks like `backend-7dcb8bd84d-cbmhq`: Deployment name, ReplicaSet hash, Pod suffix. The hash changes when the Pod template changes. The old ReplicaSet scales to 0 and a new one scales to 1. That is a rollout.

`selector.matchLabels` must select the labels in `template.metadata.labels`. Here both say `app: postgres`, `app: backend`, `app: frontend`, or `app: docs`. The selector is fixed after the Deployment is created. The ReplicaSet uses it to find its Pods. If the template labels stopped matching, the ReplicaSet would keep creating Pods and never count them.

Deleting a Pod does not delete the Deployment. The ReplicaSet sees fewer ready Pods than `replicas` and starts another from the same template.

There are no resource requests or limits in these manifests. The kubelet will schedule the Pods without reserving CPU or memory. On a shared cluster you would set `resources.requests` and `resources.limits` so one container cannot consume the node unnoticed.

## Containers and images

| Deployment | Image | Process | Listens on |
| --- | --- | --- | --- |
| `frontend` | `ai-app-frontend:latest` | nginx from `nginx:1.28-alpine`, static files from `npm run build` | 80 |
| `backend` | `ai-app-backend:latest` | `uvicorn app.main:app --host 0.0.0.0 --port 8000` as uid 10001 | 8000 |
| `postgres` | `ai-app-postgres:latest` | `postgres:18-alpine` entrypoint | 5432 |
| `docs` | `ai-app-docs:latest` | nginx serving the MkDocs HTML build | 80 |

`containers[].ports.containerPort` records the port the process listens on. It does not publish that port onto your machine, and it does not open a firewall by itself. Publishing is the job of a Service, an Ingress, or `kubectl port-forward`.

The backend image does not use the `app` script from `pyproject.toml`. That script starts uvicorn with `reload=True`, which is a development file watcher. The image command is a single server process with no watcher.

The frontend image is a production build. nginx serves files from `/usr/share/nginx/html`. There is no Vite dev server inside the Pod.

## Probes

Each container has a readiness probe and no liveness probe.

Readiness answers "should the Service send traffic here?"

| Tier | Check | Ready when |
| --- | --- | --- |
| postgres | `pg_isready -U app -d app` | The server accepts connections for database `app` |
| backend | HTTP GET `/` on port 8000 | uvicorn returns a successful status |
| frontend | HTTP GET `/` on port 80 | nginx returns the static page |
| docs | HTTP GET `/` on port 80 | nginx returns the handbook home page |

`initialDelaySeconds` waits before the first check (5s for Postgres, 3s for the others). `periodSeconds: 5` repeats the check. While the check fails, the Pod can be `Running` and still be absent from the Service endpoints. Callers of the Service then have nowhere to connect. That is why the backend Service does not send traffic to a process that is still starting.

A liveness probe would answer "should the kubelet kill and restart this container?" These manifests do not set one. A process that stays up but stops doing useful work is left running. Readiness can pull it out of the Service; only a liveness failure, or a crash, replaces the container.

## Service

Each Service has the same shape. `type` is omitted, so it is `ClusterIP`: a virtual IP that exists only inside the cluster.

```yaml
selector:
  app: backend
ports:
  - port: 8000
    targetPort: 8000
```

- `selector` chooses Pods. It looks at Pod labels, not at the Deployment name. The backend Service selects Pods with `app: backend`.
- `port` is the port clients use when they call the Service.
- `targetPort` is the port on the Pod. Here it matches `containerPort`. They can differ. If `targetPort` were 80 and `port` were 8000, clients would still call `:8000` and kube-proxy would connect to container port 80.

For the backend Service, a client inside the cluster uses `backend:8000` or the full DNS name `backend.ai-app.svc.cluster.local`. CoreDNS, which kind installs in `kube-system`, answers that name with the ClusterIP. kube-proxy on the node then forwards the connection to a ready Pod IP.

The same pattern applies to `postgres:5432` and `frontend:80`.

The set of ready Pod IPs is an EndpointSlice. Inspect it with:

```bash
kubectl -n ai-app get endpointslice
kubectl -n ai-app describe service backend
```

`describe` lists Endpoints. An empty Endpoints line means the selector matched nothing that is ready: wrong labels, the Pod is pending, or the readiness probe is failing.

These Services have no `nodePort` and no Ingress. The kind cluster was created without extra host port mappings, so `localhost` on your machine is not wired to the ClusterIPs. `kubectl port-forward` is the bridge:

```bash
kubectl -n ai-app port-forward svc/frontend 5173:80
kubectl -n ai-app port-forward svc/backend 8000:8000
kubectl -n ai-app port-forward svc/docs 8080:80
```

The first number is the port on your machine. The second is the Service `port`. Port-forward to a Service uses a ready endpoint. If the readiness probe is failing, the forward has no Pod to connect to.

Postgres is left as ClusterIP only. Database clients inside the namespace use `postgres:5432`. It is not port-forwarded, because the browser does not talk to it.

## What each tier does after the Pod is up

### Frontend

nginx serves the compiled React assets. The bundle already contains `http://127.0.0.1:8000/`. Rebuilding the frontend image is required to change that URL. Editing the Service does not change a URL that was compiled into the JavaScript.

The page load from your browser is: port-forward, Service, nginx. The following API call leaves the browser again and uses the second port-forward. The frontend Pod never opens a connection to the backend Pod.

### Backend

uvicorn binds `0.0.0.0:8000`, so it accepts connections from the Service, not only from inside the container. `GET /` returns `{"message":"Hello World"}`. CORS middleware allows that response to be read by a page served from port 5173 on localhost.

`DATABASE_URL` is in the process environment. Confirm with:

```bash
kubectl -n ai-app exec deploy/backend -- printenv DATABASE_URL
```

Nothing in `main.py` reads it. A later change that opens a Postgres connection should use the host name `postgres`, which is the Service, not `localhost`. Inside the backend Pod, `localhost` is the backend container itself.

### Postgres

The entrypoint starts the database server. The readiness command `pg_isready -U app -d app` succeeds after the server can authenticate user `app` against database `app`. From that moment the Pod is added to the `postgres` Service.

Check from inside the Pod:

```bash
kubectl -n ai-app exec deploy/postgres -- pg_isready -U app -d app
```

### Docs

`docker/docs/Dockerfile` builds this handbook with MkDocs, then copies the HTML onto nginx. The Pod is a separate container from the frontend. Service `docs` selects Pods labeled `app: docs` and exposes port 80. From your machine, port-forward local port 8080 to that Service port.

MkDocs runs only during the image build. The running container is nginx serving files from `/usr/share/nginx/html`. Editing a markdown file does not change the live site until you rebuild `ai-app-docs:latest`, load it into kind, and replace the Pod.

## Failure and recovery in this setup

| Event | What the controllers do |
| --- | --- |
| Container process exits | Kubelet restarts the container in the same Pod. The restart count increases. |
| Pod is deleted | ReplicaSet creates a new Pod from the template. |
| Deployment template changes | New ReplicaSet, new Pod. Service selector follows the labels, so traffic moves to Pods that become ready. |
| Readiness fails | Pod stays Running. Service stops using it. |
| Node image missing | Pod stays `ImagePullBackOff` or `ErrImagePull`. ReplicaSet does not switch to a different image. |
| Postgres Pod replaced | New Pod mounts `postgres-data`. Existing files are reused. |
| Namespace deleted | All of the above objects go away, including the claim and the data. |

## Commands that show each piece

```bash
kubectl get ns ai-app
kubectl -n ai-app get secret postgres
kubectl -n ai-app get pvc,pv
kubectl -n ai-app get deploy,rs,pod,svc,endpointslice
kubectl -n ai-app describe pod -l app=postgres
kubectl -n ai-app logs deploy/backend
kubectl -n ai-app get events --sort-by=.lastTimestamp
```

`logs` is the container stdout. uvicorn and the Postgres entrypoint write there. `describe pod` shows probe failures, image pull errors, and which volume is mounted. `events` is the timeline of scheduling, pulling, and starting.

## What these manifests leave unset

Intentionally absent, so the example stays on the objects above:

- No Ingress, Gateway, or LoadBalancer. Access from your machine is port-forward.
- No liveness or startup probe.
- No CPU or memory requests or limits.
- No HorizontalPodAutoscaler. Each Deployment is fixed at one replica.
- No NetworkPolicy. Any Pod in the cluster can connect to these Service ports.
- No separate Postgres operator. One Deployment runs one database process.
- The backend does not query Postgres yet. The Service, DNS name, Secret, and volume are already in place for that connection.
