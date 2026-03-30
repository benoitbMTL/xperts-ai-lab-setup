# XPERTS AI Lab Setup 🚀

Automation scripts to quickly deploy the **XPERTS AI Lab environment**:

- Windows 11
- Ubuntu 22.04.1
- FortiWeb 8.0.4

---

## Windows 🖥️

### Scripts

- `install-hoot.ps1` → Installs Hoot (Node.js + MCP client)
- `install-cherry-studio.ps1` → Installs Cherry Studio
- `add-edge-bookmarks.ps1` → Add FortiWeb lab bookmarks (Microsoft Edge)

📝 A log file is created in the **current directory** for each execution.

### Run full setup

```powershell
mkdir xperts-ai-lab; cd xperts-ai-lab; iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-hoot.ps1 -OutFile install-hoot.ps1; iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-cherry-studio.ps1 -OutFile install-cherry-studio.ps1; iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/add-edge-bookmarks.ps1 -OutFile add-edge-bookmarks.ps1; ./install-hoot.ps1; ./install-cherry-studio.ps1; ./add-edge-bookmarks.ps1
````

### Individual scripts

#### Install Hoot (MCP client)
```powershell
iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-hoot.ps1 -OutFile install-hoot.ps1; ./install-hoot.ps1
````

#### Install Cherry Studio
```powershell
iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-cherry-studio.ps1 -OutFile install-cherry-studio.ps1; ./install-cherry-studio.ps1
```

#### Add FortiWeb lab bookmarks (Microsoft Edge)
```powershell
iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/add-edge-bookmarks.ps1 -OutFile add-edge-bookmarks.ps1; ./add-edge-bookmarks.ps1
```

---

## Ubuntu 🐧

### Script

* `setup-ubuntu.sh`

### What it does

* validates Ubuntu system
* installs required packages
* installs Docker if missing
* ensures Docker is running
* deploys lab containers
* skips already running containers
* starts existing stopped containers

### Run (install)

```bash
curl -fsSL https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/setup-ubuntu.sh -o setup-ubuntu.sh && chmod +x setup-ubuntu.sh && sudo ./setup-ubuntu.sh
```

### Run (uninstall)

```bash
curl -fsSL https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/setup-ubuntu.sh -o setup-ubuntu.sh && chmod +x setup-ubuntu.sh && sudo ./setup-ubuntu.sh uninstall
```

---

## FortiWeb 🛡️

### Config file

* `fwb_system.conf`

### Setup

1. Connect to FortiWeb via SSH
2. Open CLI
3. Paste the content of `fwb_system.conf`
