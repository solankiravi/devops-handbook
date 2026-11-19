# DevOps Handbook

These pages are the notes for the local toolchain, the kind cluster, and the ai-app workloads.

This site is a static build. `docker/docs/Dockerfile` installs MkDocs, runs `mkdocs build`, and copies the HTML into an nginx image. Kubernetes runs that image as Deployment `docs` and Service `docs` in the `ai-app` namespace. The Service is ClusterIP, so open it from your machine with:

```bash
kubectl -n ai-app port-forward svc/docs 8080:80
```

Then browse `http://127.0.0.1:8080/`.

Pages that live outside `docs/` are linked into this folder so MkDocs and the files you edit stay the same file:

- `setup.md` and `tool-installation.md` at the repository root
- `ai_app/requirements.md` and `ai_app/setup.md`
