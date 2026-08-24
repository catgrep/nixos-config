# API Coverage — Phase 12: Fleet Repair

No external API integration: the detector matched "surface" against the word "API" in D-14's
description of the Radarr movie-snapshot diff.
This phase calls the pre-existing, already-integrated Radarr/Sonarr/Prowlarr REST APIs
(established in Phase 08) for operational cleanup only — exporting a movie snapshot, removing
root folders, and removing stale download-client registrations.
No new SDK, service, or API surface is onboarded in this phase.
