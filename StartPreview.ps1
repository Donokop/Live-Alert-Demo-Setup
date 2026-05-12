$SSID = "IntelDemoWLAN"
$password = "IntelDemo"
$currentWlanInfo = netsh wlan show networks
$currentSSID = $null
$scriptPath = "/IntelOpenEdge/edge-ai-suites/metro-ai-suite/live-video-analysis/showroom-demo/run-demo-alert.sh"
$composeFilePath = "/IntelOpenEdge/edge-ai-suites/metro-ai-suite/live-video-analysis/live-video-alert-agent/docker-compose.yml"

# Network configuration
$remoteHostAddress = "192.168.100.1"
$port = 9000
$remoteUser = "sshuser"
$url = "http://${remoteHostAddress}:${port}"
$remoteSSHAddress = "${remoteUser}@${remoteHostAddress}"

$tmuxSessionName = "camera-script"
$keyPath = Join-Path $HOME ".ssh\id_ed25519"

function Invoke-Cleanup {
    param(
        [string]$ComposeFilePath,
        [string]$CurrentSSID,
        [string]$RemoteSSHAddress,
        [string]$Url,
        [string]$TmuxSessionName
    )

    Write-Output "To open the site manually copy this address into your browser: $Url"
    Write-Output "Click 'Enter' to stop the Demo"
    pause

    ssh $RemoteSSHAddress "
    tmux kill-session -t '$TmuxSessionName' 2>/dev/null || true
    docker compose -f '$ComposeFilePath' down
    pkill -f camera
    "

    Write-Output "Restoring previous network"
    netsh wlan connect name="$CurrentSSID" | Out-Null
}

function Test-WiFiConnected {
    $profile = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    return $profile -and $profile.Name -eq $SSID
}

function Force-Network-Refresh {
    # Force refresh
    Start-Process "ms-availablenetworks:"
    Start-Sleep -Milliseconds 1500
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
}

function Network-Connection-Attempt {
    param (
        [string]$RemoteHostAddress
    )
    $maxAttempts = 10
    $attempt = 0
    $online = $false

    do {
        $attempt++

        try {
            Write-Output "Checking connectivity to $RemoteHostAddress..."

            # Throws on failure
            Test-Connection -ComputerName $RemoteHostAddress -Count 1 -ErrorAction Stop | Out-Null

            $online = $true
            Write-Output "Host is online."
        }
        catch [System.Net.NetworkInformation.PingException] {
            Write-Output "Ping failed: Host unreachable or not responding."
        }
        catch [System.Net.Sockets.SocketException] {
            Write-Output "DNS or network socket error."
        }
        catch {
            Write-Output "Unexpected error: $($_.Exception.Message)"
        }

        if (-not $online) {
            Start-Sleep -Seconds 2
        }

    } until ($online -or $attempt -ge $maxAttempts)

    if (-not $online) {
        Write-Output "Timed out waiting for host to come online."
    }
}

function SSH-With-Retry {
    param(
        [string]$RemoteTarget,
        [string]$RemoteCommand,
        [int]$MaxRetries = 30,
        [int]$DelaySeconds = 5,
        [switch]$StrictHostKeyChecking = $false
    )

    $sshArgs = @()

    if (-not $StrictHostKeyChecking) {
        $sshArgs += @("-o", "StrictHostKeyChecking=no")
    }

    $sshArgs += $RemoteTarget
    $sshArgs += $RemoteCommand

    $attempt = 0

    while ($attempt -lt $MaxRetries) {
        $attempt++

        Write-Output "Attempt $attempt of ${MaxRetries}: SSH -> $RemoteTarget"

        $output = ssh @sshArgs 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            return $true
        }

        if ($output -match "duplicate session") {
            Write-Output "Session already exists, continuing."
            return $true
        }

        if ($exitCode -eq 255) {
            Write-Warning "SSH transport failure."
        } else {
            Write-Warning "Remote command failed with exit code $exitCode"
        }

        Write-Warning "SSH failed (exit code $LASTEXITCODE). Retrying in $DelaySeconds seconds..."
        Start-Sleep -Seconds $DelaySeconds
    }

    throw "SSH failed after $MaxRetries attempts to $RemoteTarget"
}

$profile = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$SSID</name>
    <SSIDConfig>
        <SSID>
            <name>$SSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
    
$currentSSID = netsh wlan show interfaces |
ForEach-Object {
    $m = [regex]::Match($_, '^\s*SSID\s*:\s*(.+)$')
    if ($m.Success) {
        $m.Groups[1].Value.Trim()
    }
} | 
Select-Object -First 1

$temp="$env:TEMP\$SSID.xml"
$profile | Out-File -Encoding ascii $temp
netsh wlan add profile filename="$temp"
Write-Output "Current SSID: $currentSSID"

Write-Output "Giving $SSID highest connection priority"
netsh wlan set profileorder name="$SSID" interface="Wi-Fi" priority=1

if (!(Test-Path $keyPath)) {
    Write-Output "No ssh key found. Generating new key"

    $args = @(
        "-t", "ed25519",
        "-f", $keyPath
    )

    ssh-keygen @args

    Write-Output "SSH key created"
}

New-Item -ItemType Directory -Force "$HOME\.ssh" | Out-Null

if ($currentSSID -eq $SSID) {
    Write-Output "Already connected to the the right network"
    Network-Connection-Attempt -RemoteHostAddress $remoteHostAddress
    Write-Output "Connected successfully."
} else {
    while ($true) {
    Write-Output "Looking for $SSID..."
    Force-Network-Refresh

    if ((netsh wlan show networks) -match [regex]::Escape($SSID)) {
        Write-Output "Connecting..."
        netsh wlan connect name="$SSID" | Out-Null

        $ok = $false
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep 2

            if (Test-WiFiConnected) {
                $ok = $true
                break
            }
        }

        if ($ok) {
            Write-Output "Connected successfully."
            break
        }

        Write-Output "Failed. Retrying..."
    }
    Start-Sleep 5
}
}

Write-Output "Device reachable, starting SSH"
Write-Output "Attepting to establish ssh connection to remote host"

$remoteCommand = @'
mkdir -p ~/.ssh &&
chmod 700 ~/.ssh &&
touch ~/.ssh/authorized_keys &&
chmod 600 ~/.ssh/authorized_keys &&
cat >> ~/.ssh/authorized_keys
'@

Get-Content "$keyPath.pub" -Raw | ssh $remoteSSHAddress $remoteCommand
Write-Output "Key installed"

SSH-With-Retry -RemoteTarget $remoteSSHAddress -RemoteCommand "tmux new-session -d -s $tmuxSessionName '$scriptPath'" | Out-Null

Write-Output "Checking if Demo ready..."
Write-Output "Waiting for camera..."
while ($true) {
    $result = Test-NetConnection -ComputerName $remoteHostAddress -Port $port -WarningAction SilentlyContinue

    if ($result.TcpTestSucceeded) {
        break
    }

    Start-Sleep -Seconds 1
}

$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
)

$chrome = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
Write-Output "Demo status: Ready. Starting..."
if ($chrome) {
    Write-Output "Detected Chrome browser, launching..."
    Start-Process $chrome @("--start-fullscreen", $url)
} else {
    Write-Output "Chrome not detected, using default browser"
    Start-Process $url
}

Invoke-Cleanup -ComposeFilePath $composeFilePath -CurrentSSID $currentSSID -RemoteSSHAddress $remoteSSHAddress -Url $url -TmuxSessionName $tmuxSessionName