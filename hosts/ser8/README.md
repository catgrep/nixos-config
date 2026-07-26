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
