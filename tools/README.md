# Tools Directory

This directory contains scripts and configurations for managing required binaries (helm, helmfile, kubectl, yq) for Astrago deployment.

## Structure

```
tools/
├── download-binaries.sh    # Download binaries for your OS/arch
├── package-for-offline.sh  # Create offline deployment package
├── versions.conf           # Binary versions configuration
├── install_helmfile.sh     # Legacy installation script
└── linux/                  # Downloaded binaries (git-ignored)
```

## Online Environment Setup

For environments with internet access:

```bash
# Download all required binaries
./tools/download-binaries.sh

# Binaries will be installed to tools/linux/
```

## Offline Environment Setup

For air-gapped or offline environments:

### Step 1: Prepare offline package (on machine with internet)
```bash
# Download binaries and create package
./tools/package-for-offline.sh

# This creates: astrago-tools-offline-YYYYMMDD.tar.gz
```

### Step 2: Deploy in offline environment
```bash
# Copy the tar.gz file to offline server
scp astrago-tools-offline-*.tar.gz user@offline-server:/path/

# On offline server, extract
tar xzf astrago-tools-offline-*.tar.gz

# Run deployment
./deploy_astrago.sh
```

## Binary Versions

Current versions (defined in `versions.conf`):
- Helm: 3.16.4
- Helmfile: 0.169.2  
- Kubectl: 1.31.4
- yq: 4.44.6

To update versions, edit `versions.conf` and run `download-binaries.sh`.

## Supported Platforms

- Linux (amd64, arm64)
- macOS (amd64, arm64) - with download script
- Windows - not supported (use WSL)

## Troubleshooting

### Permission denied
```bash
chmod +x tools/*.sh
chmod +x tools/linux/*
```

### Wrong architecture
The download script auto-detects your OS and architecture. For manual download, check `versions.conf` for URLs.

### Offline package too large
The package includes all binaries (~180MB). Consider using container images for smaller distribution.

## Security

⚠️ **Important**: Always verify binary checksums in production environments.

Binary sources:
- Helm: https://github.com/helm/helm
- Helmfile: https://github.com/helmfile/helmfile
- Kubectl: https://kubernetes.io
- yq: https://github.com/mikefarah/yq