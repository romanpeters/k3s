# kubernetes

Single-node K3s running a large part of my homelab on Kairos on Proxmox using Flux.

## Development workflow

### Bootstrap

Install the required tools locally:

```bash
./scripts/bootstrap-dev.sh
```

### Pre-commit

```bash
pre-commit install
pre-commit run --all-files
```

### Validate manifests

```bash
make validate
```

### Local smoke test

```bash
make smoke
```

### Network diagram

```mermaid
flowchart TB
  subgraph "Proxmox"
    subgraph k3s["K3s Cluster"]
      subgraph "Apps Namespace"
        heimdall["Heimdall"]
        homebox["Homebox"]
        n8n["n8n"]
      end

      subgraph "Media Namespace"
        jellyfin["Jellyfin"]
        overseerr["Overseerr"]
        sonarr["Sonarr"]
        radarr["Radarr"]
        bazarr["Bazarr"]
        prowlarr["Prowlarr"]
        transmission["Transmission (+ Gluetun)"]
        tautulli["Tautulli"]
        audiobookshelf["Audiobookshelf"]
        calibre["Calibre Web"]
      end

      subgraph "Monitoring Namespace"
        changedetection["changedetection.io"]
        uptime["Uptime Kuma"]
        grafana["Grafana"]
      end

      subgraph "Infrastructure Namespace"
        authentik["Authentik"]
        homepage["Homepage"]
        homepage_tv["Homepage TV"]
      end
    end

    nginx["NGINX Webserver)"]
    plex["Plex"]
    ha["Home Assistant OS"]
    ansible["Ansible Automation Platform"]

    nginx ---|routes| k3s
    nginx --> plex
    nginx --> ha
    nginx --> ansible
  end
```
