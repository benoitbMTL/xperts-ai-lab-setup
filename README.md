# XPERTS AI Lab Setup

PowerShell automation scripts used to prepare the **XPERTS AI Lab environment**.

These scripts install required tools and configure the local browser environment for quick access to the lab applications.

All scripts:

* are written in **PowerShell**
* generate a **log file in the current directory**
* support **install and uninstall modes** where applicable
* can be executed **directly from GitHub**

---

# Scripts

## 1. install-hoot.ps1

### Objective

Installs and configures **Hoot – Postman for MCP Servers**.

The script performs the following tasks:

* installs **Node.js 20 LTS**
* installs **Hoot**
* applies the **Windows compatibility patch**
* validates installation
* writes an installation log

### Uninstall

Supported.

The script removes:

* Hoot
* Node.js (installed by the script)
* local Hoot configuration

### Log

A log file is created in the **current directory**:

```
hoot-install-YYYYMMDD-HHMMSS.log
```

or

```
hoot-uninstall-YYYYMMDD-HHMMSS.log
```

### Run (Install)

Copy and paste:

```powershell
iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-hoot.ps1 -OutFile install-hoot.ps1; ./install-hoot.ps1
```

### Run (Uninstall)

```powershell
iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-hoot.ps1 -OutFile install-hoot.ps1; ./install-hoot.ps1 -Action uninstall
```

---

# 2. install-cherry-studio.ps1

### Objective

Installs **Cherry Studio AI Desktop Client**.

The script:

* downloads the **latest Cherry Studio release**
* installs it silently
* validates installation
* writes a log

### Uninstall

Supported.

The script attempts to run the Cherry Studio uninstaller.

### Log

A log file is written in the **current directory**:

```
cherry-studio-install-YYYYMMDD-HHMMSS.log
```

or

```
cherry-studio-uninstall-YYYYMMDD-HHMMSS.log
```

### Run (Install)

```powershell
iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-cherry-studio.ps1 -OutFile install-cherry-studio.ps1; ./install-cherry-studio.ps1
```

### Run (Uninstall)

```powershell
iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-cherry-studio.ps1 -OutFile install-cherry-studio.ps1; ./install-cherry-studio.ps1 -Action uninstall
```

---

# 3. add-edge-bookmarks.ps1

### Objective

Adds the **FortiWeb lab bookmarks** to the **Microsoft Edge Favorites Bar**.

The script:

* creates a folder **FortiWeb Labs**
* adds bookmarks for the lab applications
* avoids duplicate entries
* backs up the Edge bookmarks database
* writes a log file

### Bookmarks Added

```
XPERTS Hands-on-Labs
FortiWeb Admin
Demo Tool
DVWA
Banking Application
MCP Server
Juiceshop
Petstore
Speedtest
CSP Server
```

### Uninstall

Not applicable.

The script only **adds bookmarks**.

### Log

A log file is written in the current directory:

```
edge-bookmarks-YYYYMMDD-HHMMSS.log
```

### Run

```powershell
iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/add-edge-bookmarks.ps1 -OutFile add-edge-bookmarks.ps1; ./add-edge-bookmarks.ps1
```

---

# Run Everything (Full Lab Setup)

The following command:

* creates a dedicated directory
* downloads all scripts
* executes them sequentially

Copy and paste:

```powershell
mkdir xperts-ai-lab; cd xperts-ai-lab; iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-hoot.ps1 -OutFile install-hoot.ps1; iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/install-cherry-studio.ps1 -OutFile install-cherry-studio.ps1; iwr https://raw.githubusercontent.com/benoitbMTL/xperts-ai-lab-setup/refs/heads/main/add-edge-bookmarks.ps1 -OutFile add-edge-bookmarks.ps1; ./install-hoot.ps1; ./install-cherry-studio.ps1; ./add-edge-bookmarks.ps1
```

---

# Requirements

* Windows 10 / Windows 11
* PowerShell
* Internet access
* Administrator privileges (recommended)
