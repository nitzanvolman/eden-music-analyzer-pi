# SC-OSC Windows Installation Guide

Best-effort guide for running the audio analyzer on Windows. This has not been tested on actual Windows hardware — please report issues.

## Prerequisites

- Windows 10 or later (64-bit)
- An audio input device (built-in mic, USB interface, etc.)

## Step 1: Install SuperCollider

**Option A: Chocolatey (recommended)**

```powershell
# Run PowerShell as Administrator
choco install supercollider
choco install sc3plugins
```

**Option B: Official installer**

1. Download the latest Windows installer from [supercollider.github.io/downloads](https://supercollider.github.io/downloads.html)
2. Run the installer (default path: `C:\Program Files\SuperCollider-<version>\`)
3. Download sc3-plugins from [github.com/supercollider/sc3-plugins/releases](https://github.com/supercollider/sc3-plugins/releases)
4. Extract the `SC3plugins` folder to `%LOCALAPPDATA%\SuperCollider\Extensions\`

**Note:** sclang.exe is NOT added to PATH by default. You'll need to either:
- Add the SuperCollider install directory to your PATH, or
- Use the full path (e.g., `"C:\Program Files\SuperCollider-3.13.0\sclang.exe"`)

## Step 2: Install Python 3.12+

Download from [python.org/downloads](https://www.python.org/downloads/) and run the installer. **Check "Add Python to PATH"** during installation.

Or via Chocolatey:

```powershell
choco install python --version=3.12
```

## Step 3: Set up the project

```powershell
# Clone or copy the project
git clone <repo-url> sc-osc
cd sc-osc

# Create config from template
mkdir -Force "$env:USERPROFILE\sc-osc"
Copy-Item analyzer.scd, hello.scd, test_receiver.py, config_template.env "$env:USERPROFILE\sc-osc\"
Copy-Item -Recurse sc "$env:USERPROFILE\sc-osc\sc"
Copy-Item config_template.env "$env:USERPROFILE\sc-osc\config.env"

# Create Python virtual environment
python -m venv "$env:USERPROFILE\sc-osc\.venv"
& "$env:USERPROFILE\sc-osc\.venv\Scripts\pip" install -r requirements.txt
```

## Step 4: Configure

Edit `%USERPROFILE%\sc-osc\config.env`:

```bash
SC_OSC_DESTINATIONS=127.0.0.1:9000
```

## Step 5: Run

### Test SuperCollider first

```powershell
$env:QT_QPA_PLATFORM = "offscreen"

# Adjust path to your sclang.exe:
& "C:\Program Files\SuperCollider-3.13.0\sclang.exe" "$env:USERPROFILE\sc-osc\hello.scd"
```

### Run the analyzer

```powershell
# Source config (PowerShell workaround — manually set env vars)
Get-Content "$env:USERPROFILE\sc-osc\config.env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
    }
}
$env:QT_QPA_PLATFORM = "offscreen"

& "C:\Program Files\SuperCollider-3.13.0\sclang.exe" "$env:USERPROFILE\sc-osc\analyzer.scd"
```

### Run the web server

```powershell
& "$env:USERPROFILE\sc-osc\.venv\Scripts\Activate.ps1"
python -m web.server
```

Open `http://localhost:8080` in your browser.

### Verify OSC output

```powershell
pip install python-osc
python test_receiver.py
```

## Audio Setup

Windows uses PortAudio (not JACK). SuperCollider should auto-detect your default audio device.

- **WASAPI** (default): works out of the box
- **ASIO**: lower latency, recommended for serious use. Install [ASIO4ALL](https://www.asio4all.org/) if your interface doesn't have native ASIO drivers.

To check/change audio devices, open the SuperCollider IDE (`scide.exe`) and run:

```supercollider
ServerOptions.devices;  // list available devices
```

## Known Limitations

- **Not tested on actual hardware** — this guide is based on documentation research only.
- **No autostart script** — you'll need to create a Windows Task Scheduler entry or a batch file for auto-start.
- **No systemd** — the `--systemd` flag and service management endpoints are Linux-only.
- **Chromagram UGen** — SCMIRUGens may require manual building on Windows if not included in sc3-plugins. If Chromagram fails, set `SC_FEATURE_CHROMA=0` in config.env.
- **config.env sourcing** — Windows doesn't natively source env files. Use the PowerShell snippet above or set variables manually.

## Troubleshooting

- **"sclang.exe not found"**: Add the SuperCollider install directory to your PATH.
- **"Class not defined: Chromagram"**: sc3-plugins not installed. Install via Chocolatey or manually.
- **No audio**: Check `ServerOptions.devices` in the SC IDE. Make sure the right device is selected.
- **Python venv activation fails**: Run `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` to allow script execution.
