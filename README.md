# Docker Cleanup

A Bash script to clean up unused Docker resources (stopped containers, dangling images, unused volumes, and unused networks) with detailed reporting of space reclaimed.

## Features

- Removes stopped/exited/dead containers
- Removes dangling (untagged) images, or all unused images with `-a`
- Removes unused volumes
- Removes unused custom networks
- Reports space reclaimed per category
- Dry-run mode to preview cleanup
- Verbose mode for detailed resource listing
- Safe defaults: only removes dangling images unless `-a` is specified

## Requirements

- Bash 4.0+
- Docker Engine installed and running
- User must have Docker permissions (docker group or root)

## Usage

```bash
chmod +x cleanup.sh

# Basic cleanup (dangling resources only)
./cleanup.sh

# Remove ALL unused images (not just dangling)
./cleanup.sh -a

# Dry-run with verbose output
./cleanup.sh -n -v

# Show help
./cleanup.sh -h
```

### Flags

| Flag | Description |
|------|-------------|
| `-a` | Remove all unused images, not just dangling/untagged |
| `-n` | Dry-run: show what would be removed without removing |
| `-v` | Verbose: show details about each resource |
| `-h` | Show help message |

## Sample Output

```
Docker Cleanup Tool
Timestamp: 2026-04-18 10:00:00

=== Stopped Containers ===
  Removed 3 stopped container(s)
  Space reclaimed: ~245.50 MB

=== Dangling Images ===
  Removed 5 image(s)
  Space reclaimed: ~1.23 GB

=== Unused Volumes ===
  Removed 2 volume(s)

=== Unused Networks ===
  Removed 1 network(s)

=== Summary ===
  Containers: 3
  Images:     5
  Volumes:    2
  Networks:   1
  Total space reclaimed: ~1.47 GB

Done.
```



<sub><sup>Originally developed and tested locally during learning. Later organized and pushed to GitHub for portfolio visibility.</sup></sub>
