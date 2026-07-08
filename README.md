[README.md](https://github.com/user-attachments/files/29783283/README.md)

# Lustre HPC Lab

A hands-on lab for building a working [Lustre](https://www.lustre.org/) parallel filesystem across three virtual machines using VMware Workstation. The goal is to understand — end-to-end — how the MGS, MDS, OSS, and client roles fit together, and to prove that a client on one VM can read and write files stored on an OST hosted on a different VM.

Progress is captured in a series of dated handoff notes (`handoff_1.md` … `handoff_6.md`, in Thai) so the lab can be picked up, paused, and continued across sessions.

---

## Architecture

Three VMs, each with a single Lustre role:

```
                          Host-only network (192.168.100.0/24)
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
  ┌───────────┐                 ┌────────────┐                ┌────────────┐
  │  mgsmds   │                 │    oss     │                │   client   │
  │ MGS + MDS │◀──── config ────│    OST     │                │  mounts    │
  │  MDT/sda  │                 │  OST/sdb   │                │ /mnt/labfs │
  │ .100.10   │                 │  .100.11   │                │  .100.12   │
  └───────────┘                 └────────────┘                └────────────┘
```

| VM       | Role              | Host-only IP     | Lustre disk        | Mount point   |
| -------- | ----------------- | ---------------- | ------------------ | ------------- |
| `mgsmds` | MGS + MDS         | `192.168.100.10` | `/dev/sda` (10 GB) | `/mnt/mdt`    |
| `oss`    | OSS               | `192.168.100.11` | `/dev/sdb` (10 GB) | `/mnt/ost`    |
| `client` | Lustre client     | `192.168.100.12` | — (no extra disk)  | `/mnt/labfs`  |

Filesystem name: **`labfs`** — 1 MDT + 1 OST, ~9.2 GB usable.

> **Note:** the empty Lustre disks are *not* on the same device path on both server VMs (`/dev/sda` on `mgsmds`, `/dev/sdb` on `oss`). Always confirm with `lsblk` before running `mkfs.lustre` — do not assume.

---

## Environment

| Component            | Version                                   |
| -------------------- | ----------------------------------------- |
| Hypervisor           | VMware Workstation                        |
| Guest OS             | Rocky Linux **9.4** (Minimal)             |
| Lustre               | **2.16.1** (server + client, el9.4 RPMs)  |
| Server kernel        | `5.14.0-427.31.1_lustre.el9.x86_64`       |
| Client kernel        | `5.14.0-427.13.1.el9_4.x86_64` (stock)    |
| Networking (LNet)    | `tcp0` over host-only `192.168.100.0/24`  |

Per-VM sizing: 2 vCPU, 2 GB RAM, 20 GB OS disk, plus a second 10 GB raw disk on `mgsmds` and `oss` for the MDT/OST.

Rocky 9.4 is deliberate: the Whamcloud Lustre 2.16.1 server RPMs ship a patched kernel built for el9.4. Newer minor versions of RHEL/Rocky may not have a matching prebuilt kernel.

---

## Networking

Each VM has two NICs:

- **Adapter 1 — VMware Host-only (`VMnet1`)** — carries Lustre traffic on `192.168.100.0/24` (static IPs above).
- **Adapter 2 — NAT** — DHCP, used for internet access (package installs, updates).

`VMnet1`'s subnet was changed from the default `192.168.18.0/24` to `192.168.100.0/24` via VMware's Virtual Network Editor.

`/etc/hosts` on every VM contains:

```
192.168.100.10 mgsmds
192.168.100.11 oss
192.168.100.12 client
```

For the lab, `firewalld` and SELinux are disabled on all three VMs.

---

## Bring-up (high level)

Full step-by-step commands live in the handoff notes. Short version:

1. **Provision VMs.** Install Rocky 9.4 Minimal on all three; only touch the 20 GB OS disk during install.
2. **Configure the network.** Static IPs on `ens160`, `/etc/hosts` on every VM, disable `firewalld` + SELinux.
3. **Install Lustre server.** On `mgsmds` and `oss`, install the patched kernel and Lustre server RPMs from Whamcloud (`el9.4/server/`), then reboot into the patched kernel.
4. **Install Lustre client.** On `client`, install client RPMs from Whamcloud (`el9.4/client/`) — no patched kernel needed.
5. **Format + mount MDT** on `mgsmds`:
   ```bash
   lsblk   # confirm the empty 10 GB disk
   mkfs.lustre --fsname=labfs --mgs --mdt --index=0 /dev/sda
   mkdir -p /mnt/mdt && mount -t lustre /dev/sda /mnt/mdt
   ```
6. **Format + mount OST** on `oss`:
   ```bash
   lsblk   # confirm the empty 10 GB disk (device path differs from mgsmds!)
   mkfs.lustre --fsname=labfs --ost --index=0 --mgsnode=mgsmds@tcp0 /dev/sdb
   mkdir -p /mnt/ost && mount -t lustre /dev/sdb /mnt/ost
   ```
7. **Mount from client:**
   ```bash
   mkdir -p /mnt/labfs
   mount -t lustre mgsmds@tcp0:/labfs /mnt/labfs
   ```
8. **Verify:**
   ```bash
   echo "hello lustre" > /mnt/labfs/test.txt
   cat  /mnt/labfs/test.txt
   lfs df -h
   ```

---

## Status

Proof-of-concept complete as of Day 6:

- MGS + MDT formatted and mounted on `mgsmds`
- OST formatted and mounted on `oss`
- Client mounts `labfs` and can read/write files across the network

`lfs df -h` reports a single filesystem summary of ~9.2 GB backed by 1 MDT + 1 OST.

## Roadmap

- [ ] Persistent mounts via `/etc/fstab` (currently manual)
- [ ] Reboot test — bring the whole stack back up cleanly from cold
- [ ] Failover / HA scenarios
- [ ] Multiple OSTs and/or MDTs for scale-out testing
- [ ] Performance testing (`ost-survey`, `sgpdd-survey`, large-file and concurrent workloads)

---

## Repository layout

```
.
├── README.md              # this file
├── handoff_1.md … handoff_6.md    # dated progress notes (Thai)
├── client/                # VMware VM (not tracked — see .gitignore)
├── mgsmds/                # VMware VM (not tracked — see .gitignore)
└── oss/                   # VMware VM (not tracked — see .gitignore)
```

The VMware VM directories contain multi-GB `.vmdk`, `.vmem`, and `.vmss` files that are **not** suitable for GitHub. A recommended `.gitignore`:

```gitignore
# VMware virtual machine binaries and runtime state
*.vmdk
*.vmem
*.vmss
*.vmsn
*.vmsd
*.vmx
*.vmxf
*.nvram
*.scoreboard
*.log
mksSandbox*.log
vmware*.log
client/
mgsmds/
oss/
```

If you want to share VM state, publish an appliance (OVA/OVF) as a release asset instead of committing the raw VMware files.

---

## References

- Lustre documentation — <https://doc.lustre.org/>
- Whamcloud Lustre downloads — <https://downloads.whamcloud.com/public/lustre/>
- Rocky Linux 9.4 Vault ISO — <https://dl.rockylinux.org/vault/rocky/9.4/isos/x86_64/>
