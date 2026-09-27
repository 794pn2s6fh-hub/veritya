# Erosion mod — Airlift build

This source keeps the existing Erosion tweaks, Supervision profile features and Airlift integration, and adds AirCard-style customization under **Tweaks → Experimental**:

- Airlift — existing pairing + LocalDevVPN flow.
- Wallet Cards — scan Wallet-related syslog events, assign artwork, and flash selected card artwork through the existing Airlift FFI.
- Passcode Theme — import `.passthm`, preview keypad assets, and apply TelephonyUI cache artwork.
- Wallpapers (.tendies) — import/inspect `.tendies`, detect the PosterBoard container, inject descriptors, refresh PosterBoard state and request a device respring.

The new features reuse the existing Erosion pairing file and AirliftFFI instead of adding a second pairing implementation.

Build with the existing `ipabuild.sh` / GitHub Actions workflow.
