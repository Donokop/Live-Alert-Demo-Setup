
#!/bin/bash

# Variables you can change to personalize install:
PARENT_DIRECTORY=/IntelOpenEdge
DIRECTORY_TO_SAVE_AT="$PARENT_DIRECTORY/edge-ai-suites"

GREEN='\033[0;32m'
RED='\033[0;31m'
NO_COLOR='\033[0m'

STEPS=(
	"Install dependencies"
	"Clone repositories"
	"Create access point"
	"Installed openssh server"
	"Installed project dependencies"
	"Added new user: sshuser"
	"Created fallback script"
)

for _ in "${STEPS[@]}"; do
	statuses+=("PENDING")
done
	
sudo mkdir -p "$PARENT_DIRECTORY"
cd "$PARENT_DIRECTORY"

# Install dependencies
sudo apt update
sudo apt install -y git python3 tmux
statuses[0]="DONE"

echo -e "${GREEN}Installed dependencies: git, python3 and tmux${NO_COLOR}"
# Clone repositories
if [[ ! -d "$DIRECTORY_TO_SAVE_AT/metro-ai-suite" ]]; then
	sudo git clone -b wdunia-vlm-demo https://github.com/wdunia/edge-ai-suites-prv.git
	cd edge-ai-suites-prv
	sudo git sparse-checkout set metro-ai-suite
	sudo mv "$PARENT_DIRECTORY/edge-ai-suites-prv" "$DIRECTORY_TO_SAVE_AT"
	echo -e "${GREEN}Cloned repository${NO_COLOR}"
	statuses[1]="DONE"
	
	# Set permissions so everybody can access the demo:
	sudo chmod 777 "$PARENT_DIRECTORY"
	sudo chmod 777 "$DIRECTORY_TO_SAVE_AT"
	sudo chmod 777 "$DIRECTORY_TO_SAVE_AT/metro-ai-suite"
	sudo chmod 777 "$DIRECTORY_TO_SAVE_AT/metro-ai-suite/live-video-analysis"
	sudo chmod 777 "$DIRECTORY_TO_SAVE_AT/metro-ai-suite/live-video-analysis/showroom-demo"
else
	echo "Directory already exists, skipping repository download"
	statuses[1]="EXISTED_BEFORE"
fi
cd "$DIRECTORY_TO_SAVE_AT"
cd metro-ai-suite/live-video-analysis

# Find wifi interface name
WIFI_INTERFACE=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')
if [ -z "$WIFI_INTERFACE" ]; then
	echo "No Wi-Fi interface found, skipping network configuration"
	statuses[2]="FAILED"
else
	# Create an access point
	nmcli connection add \
   	 type wifi \
   	 ifname "$WIFI_INTERFACE" \
   	 con-name IntelDemoWLAN \
   	 autoconnect yes \
   	 ssid IntelDemoWLAN


	# Configure the access point
	nmcli connection modify IntelDemoWLAN \
   	 802-11-wireless.band a \
   	 802-11-wireless.mode ap \
   	 802-11-wireless-security.key-mgmt wpa-psk \
   	 802-11-wireless-security.psk "IntelDemo" \
   	 802-11-wireless-security.pmf disable \
   	 ipv4.method shared \
   	 ipv4.addresses 192.168.100.1/24

	echo "Added network IntelDemoWLAN on interface: '$WIFI_INTERFACE'"
	statuses[2]="DONE"
fi

# Install openSSH server and start it
sudo apt install openssh-server

sudo systemctl restart ssh.service
sudo systemctl start ssh.service

echo "Installed and started openssh-server"
statuses[3]="DONE"

# Install project dependenices
cd showroom-demo
sudo chmod +x install-dependencies.sh camera-rtsp.py run-demo-alert.sh
./install-dependencies.sh
statuses[4]="DONE"

# Add new designated SSH user
SSHUSER="sshuser"
if ! id $SSHUSER &>/dev/null; then
	sudo useradd -m -s /bin/bash $SSHUSER
	statuses[5]="DONE"
else
	echo "User $SSHUSER already added"
	statuses[5]="EXISTED_BEFORE"
fi
sudo usermod -aG video $SSHUSER
sudo usermod -aG docker $SSHUSER


# Create fallback script
SSHUSER_HOME=$(getent passwd "$SSHUSER" | cut -d: -f6)
if [[ ! -d "$SSHUSER_HOME" ]]; then
	echo -e "${RED}Home directory for $SSHUSER does not exist!${NO_COLOR}"
    	statuses[6]="FAILED"
else
	sudo mkdir -p "$SSHUSER_HOME/Desktop"
	sudo chown "${SSHUSER}:${SSHUSER}" "$SSHUSER_HOME/Desktop"
	
	DEMO_SCRIPT="$DIRECTORY_TO_SAVE_AT/metro-ai-suite/live-video-analysis/showroom-demo/run-demo-alert.sh"
	
	if [[ ! -f "$DEMO_SCRIPT" ]]; then
		echo -e "${RED}Demo script not found at $DEMO_SCRIPT${NO_COLOR}"
		statuses[6]="FAILED"
	else
		sudo tee "$SSHUSER_HOME/Desktop/RunDemo.desktop" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=RunDemo
Exec=gnome-terminal -- bash -c "$DEMO_SCRIPT"
Icon=utilities-terminal
Terminal=false
EOF

		sudo chmod +x "$SSHUSER_HOME/Desktop/RunDemo.desktop"
		sudo chown "$SSHUSER:$SSHUSER" "$SSHUSER_HOME/Desktop/RunDemo.desktop" 
		sudo gio set "$SSHUSER_HOME/Desktop/RunDemo.desktop" metadata::trusted true
		statuses[6]="DONE"
	fi
fi

echo "================================================"
echo "Summary:"

for i in "${!STEPS[@]}"; do
	case "${statuses[$i]}" in
		DONE)
			COLOR=$GREEN
			;;
		EXISTED_BEFORE)
			COLOR=$GREEN
			;;
		FAILED)
			COLOR=$RED
			;;
	esac
	
	echo -e "${COLOR}${statuses[$i]}${NO_COLOR} - ${STEPS[$i]}"
done
