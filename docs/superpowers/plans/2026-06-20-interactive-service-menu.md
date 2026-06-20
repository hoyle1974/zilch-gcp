# Interactive Service Selection Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace sequential service prompts with an interactive arrow-key/space-toggle menu using `rich` for terminal UI.

**Architecture:** Add `rich` dependency, implement `get_services_interactive()` in cli.py using a loop that renders the menu, captures keyboard input, updates service state, and exits on enter. Update zilch.py to call the new function.

**Tech Stack:** `rich>=13.0.0`, `click>=8.1.0`, Python standard library `sys`, `os`

## Global Constraints

- All 16 services must be toggleable (including Cloud Build and MySQL)
- Use `rich.console.Console` for rendering
- Arrow keys wrap at list boundaries
- Current selection highlighted with color
- No sections in MVP
- Function returns updated `ZilchConfig` with all service flags set correctly

---

## File Structure

**Modified:**
- `requirements.txt` - Add rich dependency
- `cli.py` - Implement `get_services_interactive()` function
- `zilch.py` - Update line 99 to call new function

---

## Task 1: Add rich dependency

**Files:**
- Modify: `requirements.txt`

**Interfaces:**
- Produces: `rich>=13.0.0` available as import

- [ ] **Step 1: Add rich to requirements.txt**

Open `requirements.txt` and add `rich>=13.0.0` after `click>=8.1.0,<9.0.0`:

```
click>=8.1.0,<9.0.0
pydantic>=2.0.0
requests>=2.28.0
rich>=13.0.0
```

- [ ] **Step 2: Install and verify**

Run: `pip install -r requirements.txt`

Expected: `rich` installs successfully, verify with `python -c "import rich; print(rich.__version__)"`

- [ ] **Step 3: Commit**

```bash
git add requirements.txt
git commit -m "chore: add rich dependency for interactive menu"
```

---

## Task 2: Implement get_services_interactive() in cli.py

**Files:**
- Modify: `cli.py`
- Test: Manual testing via `zilch deploy`

**Interfaces:**
- Consumes: `ZilchConfig` (from `config.py`), `click` module
- Produces: Function `get_services_interactive(config: ZilchConfig) -> ZilchConfig`

### Step 1: Add imports

- [ ] **Add imports at top of cli.py**

Add these imports after existing imports (around line 9):

```python
import sys
import os
from typing import List, Dict
from rich.console import Console
from rich.style import Style
```

### Step 2: Create service list builder helper

- [ ] **Add helper function to build service list**

Add this function after `prompt_toggle()` (after line 207):

```python
def _build_service_list(config: ZilchConfig) -> List[Dict[str, str | bool]]:
    """Build list of services with current config state.
    
    Args:
        config: Current config
    
    Returns:
        List of dicts with keys: key, name, enabled
    """
    services = [
        {"key": "firestore", "name": "Firestore", "enabled": config.enable_firestore},
        {"key": "cloud_storage", "name": "Cloud Storage", "enabled": config.enable_cloud_storage},
        {"key": "secret_manager", "name": "Secret Manager", "enabled": config.enable_secret_manager},
        {"key": "firebase_auth", "name": "Firebase Auth", "enabled": config.enable_firebase_auth},
        {"key": "vertex_ai", "name": "Vertex AI", "enabled": config.enable_vertex_ai},
        {"key": "pubsub", "name": "Pub/Sub", "enabled": config.enable_pubsub},
        {"key": "cloud_tasks", "name": "Cloud Tasks", "enabled": config.enable_cloud_tasks},
        {"key": "bigquery", "name": "BigQuery", "enabled": config.enable_bigquery},
        {"key": "cloud_kms", "name": "Cloud KMS", "enabled": config.enable_cloud_kms},
        {"key": "vision_ai", "name": "Vision AI", "enabled": config.enable_vision_ai},
        {"key": "speech_to_text", "name": "Speech-to-Text", "enabled": config.enable_speech_to_text},
        {"key": "translation", "name": "Translation", "enabled": config.enable_translation},
        {"key": "scheduler", "name": "Cloud Scheduler", "enabled": config.enable_scheduler},
        {"key": "monitoring", "name": "Cloud Monitoring", "enabled": config.enable_monitoring},
        {"key": "cloud_build", "name": "Cloud Build", "enabled": config.enable_cloud_build},
        {"key": "mysql", "name": "MySQL Database", "enabled": config.enable_mysql},
    ]
    return services
```

### Step 3: Create config updater helper

- [ ] **Add helper to apply service selections back to config**

Add this function after `_build_service_list()`:

```python
def _apply_services_to_config(services: List[Dict[str, str | bool]], config: ZilchConfig) -> None:
    """Apply service selections back to config object.
    
    Args:
        services: List of service dicts with enabled state
        config: Config object to update (modified in-place)
    """
    for service in services:
        key = service["key"]
        enabled = service["enabled"]
        attr_name = f"enable_{key}"
        setattr(config, attr_name, enabled)
```

### Step 4: Create menu renderer

- [ ] **Add function to render the menu**

Add this function after `_apply_services_to_config()`:

```python
def _render_menu(console: Console, services: List[Dict[str, str | bool]], current_index: int) -> None:
    """Render the service menu.
    
    Args:
        console: Rich console for output
        services: List of service dicts
        current_index: Index of currently selected service
    """
    console.clear()
    section("Services Configuration")
    click.echo("Use arrow keys to navigate, space to toggle, enter to confirm")
    click.echo()
    
    for i, service in enumerate(services):
        checkbox = "[x]" if service["enabled"] else "[ ]"
        name = service["name"]
        
        if i == current_index:
            style = Style(color="cyan", bold=True, reverse=True)
            line = f"{checkbox} {name}"
            console.print(line, style=style)
        else:
            click.echo(f"{checkbox} {name}")
```

### Step 5: Create keyboard input handler

- [ ] **Add function to read single keypress**

Add this function after `_render_menu()`:

```python
def _get_key() -> str:
    """Read a single key from stdin.
    
    Returns:
        Key string: 'up', 'down', 'space', 'enter', or the raw character
    """
    if os.name == 'nt':  # Windows
        import msvcrt
        key = msvcrt.getch()
        if key == b'\xe0':  # Arrow key prefix on Windows
            next_key = msvcrt.getch()
            if next_key == b'H':
                return 'up'
            elif next_key == b'P':
                return 'down'
        elif key == b' ':
            return 'space'
        elif key == b'\r':
            return 'enter'
    else:  # Unix/Linux/Mac
        import tty
        import termios
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = sys.stdin.read(1)
            if ch == '\x1b':  # Escape sequence
                sys.stdin.read(1)  # Skip '['
                ch = sys.stdin.read(1)
                if ch == 'A':
                    return 'up'
                elif ch == 'B':
                    return 'down'
            elif ch == ' ':
                return 'space'
            elif ch == '\r':
                return 'enter'
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    
    return 'unknown'
```

### Step 6: Implement main interactive menu function

- [ ] **Replace get_services() with get_services_interactive()**

Replace the entire `get_services()` function (lines 91-191) with:

```python
def get_services_interactive(config: ZilchConfig) -> ZilchConfig:
    """Interactive service selection menu.
    
    Args:
        config: Current config
    
    Returns:
        Updated config with service choices
    """
    section("Services Configuration")
    
    services = _build_service_list(config)
    current_index = 0
    console = Console()
    
    while True:
        _render_menu(console, services, current_index)
        
        key = _get_key()
        
        if key == 'down':
            current_index = (current_index + 1) % len(services)
        elif key == 'up':
            current_index = (current_index - 1) % len(services)
        elif key == 'space':
            services[current_index]["enabled"] = not services[current_index]["enabled"]
        elif key == 'enter':
            break
    
    # Apply selections to config
    _apply_services_to_config(services, config)
    
    # Show summary
    console.clear()
    section("Selected Services")
    enabled = [s["name"] for s in services if s["enabled"]]
    if enabled:
        for service in enabled:
            click.echo(f"  ✓ {service}")
    else:
        click.echo("  (no services selected)")
    click.echo()
    
    return config
```

### Step 7: Verify cli.py structure

- [ ] **Check that cli.py has no syntax errors**

Run: `python -m py_compile cli.py`

Expected: No output (successful compile)

### Step 8: Commit

- [ ] **Commit the interactive menu implementation**

```bash
git add cli.py
git commit -m "feat: implement interactive service selection menu

Add arrow-key/space-toggle menu for service selection with:
- Arrow keys to navigate (wraps at edges)
- Space to toggle services on/off
- Enter to confirm and show summary
- Rich styling for current selection highlight

Replace sequential click.confirm() prompts with single interactive screen."
```

---

## Task 3: Update zilch.py to call new function

**Files:**
- Modify: `zilch.py:99`

**Interfaces:**
- Consumes: `cli.get_services_interactive()` from Task 2
- Produces: No change to return type/behavior

- [ ] **Step 1: Update function call**

In `zilch.py` at line 99, change:

```python
# FROM:
config = cli.get_services(config)

# TO:
config = cli.get_services_interactive(config)
```

- [ ] **Step 2: Verify no syntax errors**

Run: `python -m py_compile zilch.py`

Expected: No output (successful compile)

- [ ] **Step 3: Commit**

```bash
git add zilch.py
git commit -m "refactor: use new interactive service menu

Update deploy command to call get_services_interactive() instead of get_services()."
```

---

## Task 4: Manual test the interactive menu

**Files:**
- Test: Integration test via `zilch deploy --dry-run`

**Interfaces:**
- Consumes: Working implementation from Tasks 1-3
- Produces: Verified interactive menu behavior

- [ ] **Step 1: Verify menu displays**

Run: `python zilch.py deploy --dry-run` (or `zilch deploy --dry-run` if installed)

At the services prompt, verify:
- Menu displays all 16 services
- Services show `[x]` (enabled) or `[ ]` (disabled)
- Current selection is highlighted in cyan/bold/reversed

- [ ] **Step 2: Test arrow key navigation**

Press up/down arrows and verify:
- Selection moves up/down one item at a time
- Selection wraps from last item to first when pressing down
- Selection wraps from first item to last when pressing up
- Cyan highlight follows the current selection

- [ ] **Step 3: Test space toggle**

Position on a disabled service and press space. Verify:
- `[ ]` changes to `[x]`
- Highlight stays on the same item
- Press space again, verify it changes back to `[ ]`

- [ ] **Step 4: Test enter to exit**

After toggling a few services, press enter. Verify:
- Menu closes
- Summary shows selected services with `✓` checkmark
- All toggled services appear correctly in summary
- Deployment continues to next step

- [ ] **Step 5: Verify config is applied**

Run with `--auto` flag to skip all prompts and see what the auto-applied config uses:

Run: `python zilch.py deploy --dry-run --auto`

Then manually run and note which services you enable/disable in the menu. Re-run and load `.zilch.config` to verify the saved config matches your menu selections.

- [ ] **Step 6: Create summary of test results**

Document what was tested and confirmed working. No commit needed for testing.

---

## Task 5: Final verification and edge cases

**Files:**
- Test: Edge case testing

**Interfaces:**
- Consumes: Working implementation from Tasks 1-4
- Produces: Confidence that implementation is solid

- [ ] **Step 1: Test with no services enabled**

Run the menu and disable all services (toggle all from [x] to [ ]). Press enter and verify:
- Summary shows "(no services selected)"
- Config saves correctly
- No errors

- [ ] **Step 2: Test with all services enabled**

Run the menu and enable all services. Press enter and verify:
- Summary shows all 16 services with ✓
- Config saves correctly

- [ ] **Step 3: Verify Cloud Build and MySQL are toggleable**

Confirm that Cloud Build and MySQL appear in the menu and can be toggled (unlike the old behavior where Cloud Build was marked "always available").

- [ ] **Step 4: Test existing scheduler/monitoring config flows**

If MySQL is toggled on:
- Verify that post-menu config collection still triggers
- Scheduler config should prompt if enabled
- Monitoring config should prompt if enabled

Run with a config that has these enabled and verify the prompts still appear after the menu.

- [ ] **No commit needed** - Verification only

---

## Success Checklist

- [ ] Rich dependency added to requirements.txt
- [ ] `get_services_interactive()` implemented with all helpers
- [ ] Arrow keys navigate with wrapping
- [ ] Space toggles services
- [ ] Enter exits with summary
- [ ] All 16 services present and toggleable
- [ ] Current selection highlighted
- [ ] Config updated correctly
- [ ] zilch.py calls new function
- [ ] Manual testing confirms all behaviors work
- [ ] Edge cases verified (no services, all services, Cloud Build, MySQL)
- [ ] Scheduler/monitoring flows still work when enabled
