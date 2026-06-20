# Interactive Service Selection Menu Design

**Date:** 2026-06-20  
**Status:** Approved  
**Scope:** Replace sequential service prompts with interactive terminal menu

## Overview

Currently, service selection in `zilch deploy` uses sequential `click.confirm()` prompts organized by sections. This design replaces that with a single interactive menu where users navigate a flat list of services using arrow keys, toggle selections with space, and exit with enter.

## User Flow

1. **Display Menu:** Show all services in a flat list, one per line
   - Format: `[ ] Service Name` (disabled) or `[x] Service Name` (enabled)
   - Current selection highlighted with color
   - Wraps at edges (down from last item → first item, up from first → last)

2. **Navigate:** Arrow up/down to move selection
   - Selection wraps around list boundaries
   - Current item highlighted in color (via `rich` styling)

3. **Toggle:** Space key toggles current service on/off
   - Updates display immediately ([ ] ↔ [x])

4. **Exit:** Enter key exits menu
   - Shows summary of selected services
   - Returns updated config to caller

## Architecture

### Files Changed
- `cli.py`: Replace `get_services()` with interactive version
- `requirements.txt`: Add `rich>=13.0.0`

### Implementation Details

**Service Data Structure:**
```python
services = [
    {"key": "firestore", "name": "Firestore", "enabled": bool},
    {"key": "cloud_storage", "name": "Cloud Storage", "enabled": bool},
    {"key": "secret_manager", "name": "Secret Manager", "enabled": bool},
    {"key": "firebase_auth", "name": "Firebase Auth", "enabled": bool},
    {"key": "vertex_ai", "name": "Vertex AI", "enabled": bool},
    {"key": "pubsub", "name": "Pub/Sub", "enabled": bool},
    {"key": "cloud_tasks", "name": "Cloud Tasks", "enabled": bool},
    {"key": "bigquery", "name": "BigQuery", "enabled": bool},
    {"key": "cloud_kms", "name": "Cloud KMS", "enabled": bool},
    {"key": "vision_ai", "name": "Vision AI", "enabled": bool},
    {"key": "speech_to_text", "name": "Speech-to-Text", "enabled": bool},
    {"key": "translation", "name": "Translation", "enabled": bool},
    {"key": "scheduler", "name": "Cloud Scheduler", "enabled": bool},
    {"key": "monitoring", "name": "Cloud Monitoring", "enabled": bool},
    {"key": "cloud_build", "name": "Cloud Build", "enabled": bool},
    {"key": "mysql", "name": "MySQL Database", "enabled": bool},
]
```

**Function Signature:**
```python
def get_services_interactive(config: ZilchConfig) -> ZilchConfig:
    """Interactive service selection menu with arrow keys and space toggle."""
    # Build service list from config state
    # Display loop: render menu, handle input, update state
    # On exit: show summary, return updated config
```

**Display Loop:**
- Render menu with current selection highlighted
- Handle keyboard input (↑, ↓, space, enter)
- Update state and re-render
- Exit on enter key

**Terminal Rendering:**
- Use `rich.console.Console` to render menu
- Use `rich.style.Style` to highlight current selection
- Clear screen between renders for clean UX

## Integration Points

**Caller:** `zilch.py` line 99 calls `cli.get_services(config)`  
**Replacement:** Call `cli.get_services_interactive(config)` instead

**Post-Service Config:**
- If `config.enable_scheduler` → call `get_scheduler_config()`
- If `config.enable_monitoring` → call `get_monitoring_config()`
- If `config.enable_mysql` → handled in existing flow

These remain unchanged; the interactive menu only affects service *toggling*, not post-selection config collection.

## Behavior Notes

- **All services toggleable:** Including Cloud Build and MySQL (unlike current code which marks Cloud Build as "always available")
- **Flat list:** No sections in MVP (can be added later if desired)
- **Color highlighting:** Current selection uses rich colors (e.g., cyan background or bright text)
- **Wrapping:** Arrow keys wrap at list boundaries
- **No re-entry:** Once user presses enter and menu closes, service selection is complete

## Success Criteria

- [ ] User can navigate menu with arrow keys
- [ ] User can toggle services with space key
- [ ] User can exit with enter key
- [ ] Selection wraps at edges
- [ ] Current selection is visually highlighted
- [ ] Summary shown after exit
- [ ] Config returned with correct service states
- [ ] All 16 services available (including Cloud Build and MySQL)

## Out of Scope (MVP)

- Sections/categorization (can be added after MVP works)
- Search/filter functionality
- Service descriptions in the menu itself
- Mouse support
- Custom key bindings
