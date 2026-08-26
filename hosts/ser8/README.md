## Storage Architecture

ser8 uses ZFS exclusively for persistent storage, split across four pools/datasets:

- `rpool` — the system disk (NVMe).
Holds the OS, the Nix store, and impermanence's rollback-on-boot root filesystem.
- `backup` — a four-disk RAID-Z2 pool.
Holds household application backups and Frigate's camera recordings and clips.
- `media` — a two-disk mirror.
Holds the full media library (movies, TV, music, books) as a single dataset, mounted at `/mnt/media`.
It is one dataset rather than one per library because the old reason for that split — letting hardlinks cross directories for torrent seeding — no longer applies now that torrenting is retired; completed downloads are copied in during import instead of hardlinked.
- `rpool/safe/downloads` — NVMe staging for in-progress and completed downloads, mounted at `/mnt/downloads`, with a hard quota so a stuck or oversized import can never again bloat the media mirror.
SABnzbd and NZBGet write here; Radarr and Sonarr import from here into the mirror.

## Accessing Media Drive over SMB

### MacOS

Go to `Finder` > `Go` > `Connect to Server` (or `Command + K`)

Type in:
```
smb://media@ser8.local
```

And login as the `media` user.

## Bazarr initial setup

Open `https://bazarr.vofi` after deploying the ser8, firebat, and pi4 configurations.

In **Settings > Sonarr**, enable Sonarr at `127.0.0.1:8989` and copy the API key from Sonarr.
Leave path mappings empty because Sonarr and Bazarr both see `/mnt/media/tv` directly.

Create an English language profile and make it the default for new series.
Configure the subtitle providers you want to use.
Store subtitles alongside media files.
Enable UTF-8 conversion and adaptive searching.
Choose whether embedded subtitles satisfy the profile.

Existing series need the new profile assigned with **Series > Mass Edit**.
After assigning it, use **Wanted > Series > Search All** to start the first library search.
