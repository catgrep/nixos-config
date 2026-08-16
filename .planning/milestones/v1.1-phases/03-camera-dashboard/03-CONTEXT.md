# Phase 3: Camera Dashboard - Context

**Gathered:** 2026-02-10
**Status:** Ready for planning

<domain>
## Phase Boundary

HA dashboard for live camera monitoring, detection event browsing, and per-camera detection toggles. Covers all 3 Frigate cameras (driveway, front_door, garage). Creating new automations, notification changes, or additional integrations are separate phases.

</domain>

<decisions>
## Implementation Decisions

### Feed layout
- Equal grid layout for 3 cameras — no camera prioritized over others
- Tabbed views: separate "Live Cameras" tab and "Events" tab (not a single scrollable page)
- Fixed priority order: driveway first, then front_door, then garage
- Single column on mobile (HA Companion app) — stack cameras vertically for larger individual feeds

### Event browsing
- Thumbnail grid of detection event snapshots with camera name + timestamp
- Filterable by both camera (driveway, front_door, garage) AND object type (person, car, package)
- Show last 7 days of event history
- Clicking an event thumbnail expands it inline in the dashboard with larger snapshot and event details (not a link to Frigate UI)

### Camera card style
- Use Frigate Lovelace card (frigate-hass-card) — purpose-built for Frigate integration
- Live video stream by default (not snapshots)
- Click/tap a camera to expand to fullscreen view
- No bounding box overlays on live feeds — clean camera view, detections shown only in events tab

### Detection controls
- Separate controls section below camera grid (not inline on cards)
- Master toggle for all cameras + individual per-camera toggles
- Both object detection AND motion detection toggles per camera
- "Detection Off" overlay badge on camera feed when detection is disabled for that camera

### Claude's Discretion
- Frigate card configuration details and stream protocol
- Mobile responsive breakpoints
- Controls section styling and layout
- Event thumbnail grid sizing and pagination approach

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-camera-dashboard*
*Context gathered: 2026-02-10*
