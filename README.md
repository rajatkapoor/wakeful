# Wakeful

A menu bar app that turns any Mac into an always-on, reachable machine: it checks every setting that matters, fixes most of them with one click (one admin password prompt), and walks you through the rest in System Settings.

Universal binary (Apple silicon + Intel), macOS 11 Big Sur or later.

## What it checks

| Item | How it's fixed |
|---|---|
| Never sleep automatically | `pmset sleep 0` (laptops: charger profile only) |
| Wake for network access | `pmset womp 1` |
| Start up after a power failure (desktops) | `pmset autorestart 1` |
| Power Nap off (optional) | `pmset powernap 0` |
| Stay awake with the lid closed (laptops, optional) | `pmset disablesleep 1` |
| Remote Login (SSH) | tries `systemsetup`/`launchctl`, falls back to opening Sharing settings with instructions |
| Screen Sharing (optional) | guided: macOS won't let apps turn this on |
| Automatic login after restart | guided: needs your password; impossible while FileVault is on |
| Start Wakeful at login | LaunchAgent in `~/Library/LaunchAgents` |
| Tailscale (optional) | link to install, for SSH from outside your network |

Fix All also sets "restart automatically if the computer freezes".

The menu also has a **Keep Awake Now** switch (on by default). It holds a power assertion, like `caffeinate`, so the Mac stays awake even before you enter the admin password. It also shows the hostname and IP, and has a Copy SSH Command item.

Status reads: ✅ done · ⚠️ one click fixes it · 👉 you need to do it in System Settings · ⚪️ optional and not set.

## Build

```sh
./build.sh        # → build/Wakeful.app and build/Wakeful.zip
```

## Install on another Mac

1. Copy `build/Wakeful.zip` over (AirDrop, USB, `scp`), unzip, and move `Wakeful.app` to /Applications.
2. The app is ad-hoc signed, not notarized, so Gatekeeper blocks the first launch. Either:
   - open it once, then go to System Settings → Privacy & Security and click **Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/Wakeful.app`
3. Launch it. The setup window opens, so click **Fix All**.
