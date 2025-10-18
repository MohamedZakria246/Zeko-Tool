# Zeko-Tool: Bash Pentesting Automation Suite

**Zeko Tool** is a comprehensive command-line suite built using **Bash** scripting for penetration testing (pentesting). It automates and simplifies critical security tasks, providing a unified interface for popular penetration testing utilities.

The primary goal is to provide rapid automation for reconnaissance, port scanning, web enumeration, and payload generation.

## 🚀 Key Features

* **Cross-Platform Support:** Automatically detects and uses the correct package manager (`apt`, `dnf`, or `yum`) for tool installation, making it fully functional on **Kali/Ubuntu/Debian** and **CentOS/RHEL/Fedora**.
* **Comprehensive Scanning:** Integrates leading tools like **Nmap**, **Masscan**, and the faster port scanner **RustScan**.
* **Web & Directory Fuzzing:** Centralizes directory and file hunting with **Gobuster**, **Dirb**, and **FFUF**, along with web security scanning via **Nikto** and **WhatWeb**.
* **Authentication Attacks:** Easy-to-use menus for running brute-force attacks against services (e.g., SSH, FTP) using **Hydra**.
* **Exploitation Workflow:** Simplifies **MSFvenom** payload generation and sets up listeners using **Netcat** or **MSFconsole**.
* **Organized Results:** Automatically saves all scan and command outputs to an organized, timestamped directory (`./results`).

## 🛠️ Installation and Setup

### Prerequisites

* A Linux operating system (Kali/Ubuntu/Debian or CentOS/RHEL/Fedora).
* `sudo` privileges.

### Steps to Run

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/YourUsername/Zeko-Tool.git](https://github.com/YourUsername/Zeko-Tool.git)
    cd Zeko-Tool
    ```
2.  **Grant Execution Permissions:**
    ```bash
    chmod +x zeko_Tool_V3_Updated.sh
    ```
3.  **Execute the Tool:**
    ```bash
    ./zeko_Tool_V3_Updated.sh
    ```

> **Note:** When you select a menu option for a tool that is not installed (e.g., `nmap`), the script will automatically detect your distribution's package manager (`apt`, `dnf`, or `yum`) and ask for permission to install the required package.

## 📜 Tools Integrated

This tool streamlines the use of core pentesting utilities, including:

* `nmap`
* `masscan`
* `rustscan`
* `gobuster`
* `nikto`
* `hydra`
* `msfvenom`
* `searchsploit`
* `enum4linux`
* `whatweb`
* and more...

---

## 🤝 Contribution

Contributions, suggestions, and bug reports are welcome! Please feel free to open an **Issue** or submit a **Pull Request**.
