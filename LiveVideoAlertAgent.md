# Live Video Alert Agent – Remote Preview Setup

This guide explains how to run the Live Video Alert Agent demo on an Ubuntu host
and remotely preview it from a Windows client

## Overview
The Ubuntu machine:
 - hosts the demo
 - creates a Wi-Fi access point
 - streams the preview

The Windows machine:
 - connects to the Ubuntu access point
 - remotely starts the demo
 - opens the preview stream

## Architecture / What this setup does

Data flow:
Camera / video source → Ubuntu processing pipeline → RTSP/Web preview stream → Windows client

Communication between Ubuntu and Windows is handled via SSH for remote script execution and HTTP/RTSP for preview streaming
## Prerequisites
 - Ubuntu 24.04
 - Windows 11
 - Internet connection

## Ubuntu Host Setup
### Install Dependencies
```bash
sudo apt update
sudo apt install -y git python3 tmux
```

### Clone Repository
```bash
git clone -b wdunia-vlm-demo https://github.com/wdunia/edge-ai-suites-prv.git
cd edge-ai-suites-prv
git sparse-checkout set metro-ai-suite
cd metro-ai-suite/live-video-analysis/live-video-alert-agent
```

### Configure Access Point
Create the access point:

> NOTE: Replace 'wlan0' with you actual wireless interface

```bash
nmcli connection add \
    type wifi \
    ifname wlan0 \
    con-name IntelDemoWLAN \
    autoconnect yes \
    ssid IntelDemoWLAN
```

Configure the access point:

```bash
nmcli connection modify IntelDemoWLAN \
    802-11-wireless.band a \
    802-11-wireless.mode ap \
    802-11-wireless-security.key-mgmt wpa-psk \
    802-11-wireless-security.psk "IntelDemo" \
    802-11-wireless-security.pmf disable \
    ipv4.method shared \
    ipv4.addresses 192.168.100.1/24
```

Enable the access point:

```bash
nmcli connection up IntelDemoWLAN
```

After enabling the access point, verify that:

- A Wi-Fi network named `IntelDemoWLAN` should appear
- The Ubuntu host should have IP `192.168.100.1`
- Windows should be able to connect using the configured password
### Configure SSH server
Install openSSH server:
```bash
sudo apt install openssh-server
```

Start the openSSH server:
```bash
sudo systemctl restart ssh.service
sudo systemctl start ssh.service
```

To check if openSSH is running:
```bash
sudo systemctl status ssh.service
```

### Configure SSH User
Create a new designated SSH user:
```bash
sudo useradd -m sshuser
sudo passwd sshuser
```

Add the SSH user to the `video` group so it can access camera devices remotely
```bash
sudo usermod -aG video sshuser
```

### Install Project Dependencies
Change to the downloaded repository directory: `edge-ai-suites-prv/metro-ai-suite/live-video-analysis/showroom-demo`

```bash
cd edge-ai-suites-prv/metro-ai-suite/live-video-analysis/showroom-demo
```

Make project scripts executable: `edge-ai-suites-prv/metro-ai-suite/live-video-analysis/showroom-demo`

```bash
chmod +x install-dependencies.sh camera-rtsp.py run-demo-alert.sh
```

Install the project dependencies:
```bash
./install-dependencies.sh
```

### Create Fallback Script
Switch to SSH user and open a terminal

Change directory to:
```bash
cd ~/Desktop
```

Create a new file with the text editor of your choice:
```
nano RunDemo.desktop
```

Contents of the file:
> NOTE: replace the `edge-ai-suites-prv/.../run-demo-alert.sh` path with the absolute path to the `run-demo-alert.sh` location
```
[Desktop Entry]
Type=Application
Name=RunDemo
Exec=gnome-terminal -- bash -c "edge-ai-suites-prv/metro-ai-suite/live-video-analysis/showroom-demo/run-demo-alert.sh"
Icon=utilities-terminal
Terminal=false
```

Expected result:
- Double-clicking on the RunDemo file causes the demo to open in a browser

## Windows Client Setup
### Required Files
Download `RunDemo.bat` and `StartPreview.ps1` from [place_holder]

> NOTE: Both files should be in the same directory
### Configure StartPreview.ps1

Edit `StartPreview.ps1`

 - `$password` 
    - Use the same password configured in
        [Create Access Point](#configure-access-point)

 - `$remoteHostAddress`
   - Use the IP address configured in
        [Create Access Point](#configure-access-point)

 - `$scriptPath`
    - Change this to the absolute path to `run-demo-alert.sh` file on Ubuntu

 - `$composeFilePath`
    - Change this to the absolute path to `live-video-alert-agent/docker-compose.yml` file on Ubuntu

 - `$remoteUser`
   - Use the username created in
        [Create SSH User](#configure-ssh-user)
 - `$port`
    - If you did not modify the Docker Compose port settings the default port is `9000`

### Run the Demo
If everything is set up correctly, double-clicking the `RunDemo.bat` file should be enough to start the preview. When prompted for an SSH password, enter the password used when the SSH user was created

## Verification Steps

After setup, verify the following:
1. Access point is active
    - You should see IntelDemoWLAN on the client device

2. SSH access works
```bash
ssh sshuser@192.168.100.1
```

3. Demo services are running:
```bash
docker ps
```

4. Preview stream (adjust IP/port if needed):
http://192.168.100.1:9000

## Troubleshooting

### Access point does not appear

Check whether the wireless adapter supports AP mode:

```bash
iw list | grep AP
```

### Permission denied when accessing camera

Verify the user belongs to the `video` group:

```bash
groups sshuser
```

### Windows cannot connect over SSH

Verify the Ubuntu host IP:

```bash
ip addr
```

Check SSH service:

```bash
sudo systemctl status ssh.service
```

## Security Notes
 - SSH user sshuser has __no sudo privileges__ by default
 - SSH is intended for trusted local devices only
 - Change default passwords before any external or production use

## Known Issues

### Windows 11 cannot connect to remote preview
- SYMPTOMS:
    - Running the script does not open the browser
    - SSH connection fails (`port 22 unreachable`)
- CAUSE: 
    - Wi-Fi AP mode compatibility issues on some adapters
    - Driver limitations in monitor/AP mode combinations
- WORKAROUND: 
    - Ensure `802-11-wireless-security.pmf disable`
    - Reconnect Windows client to IntelDemoWLAN
    - If needed restart NetworkManager:
        - sudo systemctl restart NetworkManager

### Windows 11 suddenly switches to another network
- SYMPTOMS:
    - During script execution there are sudden netowrk errors
    - The Demo video at times stops/freezes
- CAUSE:
    - Unknown
- WORKAROUND:
    - Changing the AP band to 5GHz seems to cause the connection to become more stable
        - nmcli connection modify IntelDemoWLAN 802-11-wireless.band a

### No video when remotely starting the preview
- SYMPTOMS:
    - Webpage opens in browser, but there is no video
- CAUSE:
    - Remote user not in `video` group
- WORKAROUND:
    - Ensure remote user is in `video` group
        - sudo usermod -aG video sshuser