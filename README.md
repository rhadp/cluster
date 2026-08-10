# Red Hat Automotive Suite

> **One-command deployment of a complete automotive development platform on OpenShift**

This repository deploys the [Red Hat Automotive Suite](https://github.com/rhadp) (RHAS) — a cloud-native development environment for automotive software — onto a fresh OpenShift cluster using Ansible and GitOps.

**What gets deployed:** An OpenShift cluster with TLS (cert-manager + Let's Encrypt), SSO (Red Hat Build for Keycloak), and OpenShift GitOps (ArgoCD) as infrastructure. On top of that, three optional platform components are deployed via ArgoCD: Red Hat Dev Spaces (CDE), Jumpstarter (HIL testing), and the RHAS Builder operator (RHIVOS image builds).

## Quick Start

### 1. Prerequisites

| Requirement | Details |
|---|---|
| Python 3.9+ | With `pip` and `venv` |
| Cloud account | AWS or GCP with sufficient quota |
| Red Hat pull secret | From [console.redhat.com/openshift](https://console.redhat.com/openshift/create) |
| DNS domain | A base domain delegated to your cloud provider (e.g. Route 53) |

### 2. Clone and set up

```bash
git clone https://github.com/rhadp/cluster.git
cd cluster

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Configure

```bash
cp inventory/secrets/.env.example inventory/secrets/.env
```

Edit `inventory/secrets/.env` and set at minimum:

```bash
CLOUD_PROVIDER=aws                              # aws or gcp
CLUSTER_TOPOLOGY=default                        # default or compact (see Configuration)
CLUSTER_VERSION=4.22.6                          # OpenShift version to deploy
CLUSTER_BASE_DOMAIN=rhas.example.com            # your DNS domain
AWS_ACCESS_KEY_ID=...                           # cloud credentials
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=eu-central-1
LETSENCRYPT_EMAIL=you@example.com               # for TLS certificates
```

For GCP, replace the AWS variables with `GCP_SERVICE_ACCOUNT_KEY_FILE`, `GCP_SERVICE_ACCOUNT_EMAIL`, `GCP_PROJECT_ID`, `GCP_ORGANIZATION_ID`, and `GCP_DEFAULT_REGION`. See [inventory/secrets/.env.example](inventory/secrets/.env.example) for all available options.

Save your Red Hat pull secret to `inventory/secrets/pull-secret.txt`.

### 4. Deploy

```bash
./install.sh
```

Takes **60–90 minutes**. The deployment runs through these stages:

1. Download the OpenShift installer
2. Provision the cluster on your cloud provider
3. Configure TLS certificates (cert-manager + Let's Encrypt)
4. Configure SSO authentication (Keycloak)
5. Set up GitOps (ArgoCD)
6. Deploy platform components (Dev Spaces, Jumpstarter, Builder)

### 5. Access

After deployment:

- **OpenShift console:** `https://console-openshift-console.apps.<cluster_name>.<domain>`
- **Default admin login:** `admin` / `openshift`
- **Kubeconfig:** `~/.openshift/<cluster_name>/auth/kubeconfig`

Where `<cluster_name>` is the value of `RHAS_CLUSTER_NAME` (default: `rhas`) and `<domain>` is your `CLUSTER_BASE_DOMAIN`.

Override the default credentials via `DEFAULT_ADMIN_USER` and `DEFAULT_ADMIN_PASSWORD` in `.env`. The `kubeadmin` bootstrap user is removed after deployment.

## Configuration

All configuration is driven by two files:

- **`inventory/secrets/.env`** — Cloud credentials, cluster name, domain, topology, and component toggles. See [inventory/secrets/.env.example](inventory/secrets/.env.example) for all options.
- **`inventory/platform.yml`** — GitOps repository settings, namespace prefixes, and group definitions.

The correct architecture inventory file (`arch-<topology>-<cloud>.yml`) is automatically selected based on `CLUSTER_TOPOLOGY` and `CLOUD_PROVIDER` from your `.env`.

### Topology and architecture

| Topology | Set via | Nodes | Architecture | Description |
|---|---|---|---|---|
| `default` | `CLUSTER_TOPOLOGY=default` | 3 control plane + 2 workers | Multi-arch (amd64) | Dedicated worker nodes; supports optional ARM and baremetal workers |
| `compact` | `CLUSTER_TOPOLOGY=compact` | 3 nodes (dual-role) | arm64-only | Control plane nodes double as workers |

Additional options for the `default` topology:

| Variable | Description |
|---|---|
| `CLUSTER_ARM_NODES=true` | Add ARM worker nodes |
| `CLUSTER_BAREMETAL_NODES=true` | Add baremetal worker nodes (AWS only) |
| `CLUSTER_VIRT=true` | Enable CNV on baremetal nodes |

### Platform components

All three platform components are deployed by default. Disable any of them in `.env`:

| Variable | Component | Default |
|---|---|---|
| `PLATFORM_DEPLOY_DEVSPACES` | Red Hat Dev Spaces | `true` |
| `PLATFORM_DEPLOY_JUMPSTARTER` | Jumpstarter | `true` |
| `PLATFORM_DEPLOY_BUILDER` | RHAS Builder | `true` |

### GitOps customization

Platform components are deployed via ArgoCD using manifests from the [rhadp/manifests](https://github.com/rhadp/manifests) repository (`main` branch by default). To customize the deployed components:

1. **Fork** [rhadp/manifests](https://github.com/rhadp/manifests) into your own organization.
2. **Make changes** in your fork (modify component configurations, add overlays, etc.).
3. **Update** `inventory/platform.yml` to point to your fork:

```yaml
platform_gitops_repo_url: "https://github.com/your-org/manifests"
platform_gitops_repo_revision: "your-branch"
```

4. **Redeploy** the platform components:

```bash
./platform.sh
```

This applies your manifest changes without reprovisioning the underlying cluster.

## Lifecycle

| Command | Purpose |
|---|---|
| `./install.sh` | Full end-to-end deployment (provision cluster + deploy platform) |
| `./platform.sh` | Redeploy platform components on an existing cluster |
| `./destroy.sh` | Tear down the entire cluster and cloud resources |

## Contributing

Contributions welcome! Fork the repository and submit a pull request. Check the [Issues](https://github.com/rhadp/cluster/issues) and the [project board](https://github.com/orgs/rhadp/projects/1) for planned work.

## Disclaimer

This is not an officially supported Red Hat product.

## License

See [LICENSE](LICENSE) file for details.
