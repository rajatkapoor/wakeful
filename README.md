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

## Updates

Wakeful checks for updates once a day, and from **Check for Updates…** in the menu, using [Sparkle](https://sparkle-project.org). When a new version is found, the menu shows "Update Available" and Sparkle offers to install and relaunch.

- Each GitHub release on this repo carries the zip and the update feed (`appcast.xml`). The app reads `releases/latest/download/appcast.xml`, so the newest release is what installed copies are offered.
- Every update zip is signed with an EdDSA key stored in the login keychain (Sparkle account `wakeful`). The app only installs updates signed with that key, from the same Developer ID.
- The key is backed up outside this repo. Never generate a new one: existing installs would reject every update. To restore it on a new Mac, save it to a file, run `vendor/Sparkle/bin/generate_keys --account wakeful -f <file>`, then delete the file.

## Build

```sh
./build.sh                    # ad-hoc signed, for local testing → build/Wakeful.app
```

## Release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` (+1) in `Resources/Info.plist`, and commit.
2. `scripts/release.sh "What changed"`

This builds, signs with Developer ID, notarizes, signs the update for Sparkle, writes `appcast.xml`, tags the commit, and publishes the GitHub release. Installed copies pick it up within a day.

## Install on another Mac

Download the latest zip from [Releases](https://github.com/rajatkapoor/wakeful/releases/latest), unzip, move `Wakeful.app` to Applications, open it and click **Fix All**. Builds are notarized, so there's no Gatekeeper warning.
