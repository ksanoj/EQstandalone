# EQstandalone

A collection of standalone Lua scripts for EverQuest that don't fit anywhere else.  These scripts are designed to work with MacroQuest and provide helpful automation and debugging utilities. 

## Scripts

### 🐾 Sentry (`sentry.lua`)

An automated pet attack script with a graphical user interface. 

![Pet Auto Attack GUI](images/sentry_gui.png)

**Features:**
- Automatically commands your pet to attack the nearest NPC within a configurable range
- ImGui-based GUI for easy control
- Adjustable attack distance (0-400 units)
- Toggle on/off functionality
- 2-second attack interval to prevent spam

**Usage:**
```
/lua run sentry
```

**GUI Controls:**
- **Enable Pet Attack** - Toggle automatic pet attacks on/off
- **Attack Distance** - Slider to set the maximum distance for target detection
- **Stop Script** - Terminates the script

---

### 🔍 Spawn Debug (`spawndebug.lua`)

A debugging tool for monitoring NPC spawns within a configurable radius.

![Spawn Debug GUI](images/spawndebug_gui.png)

**Features:**
- Real-time spawn detection and logging
- Configurable detection radius (0-150 units)
- Displays spawn ID, name, distance, and timestamp
- Scrollable table view of all detected spawns
- Clear button to reset the spawn list

**Usage:**
```
/lua run spawndebug
```

**GUI Controls:**
- **Detection Radius** - Slider to adjust the monitoring range
- **Clear** - Clears the spawn list and resets tracking

---

## Requirements

- [MacroQuest](https://www.macroquest.org/)
- Lua plugin enabled

## Installation

1. Download the desired `.lua` file(s)
2. Place them in your MacroQuest `lua` folder
3. Run in-game using `/lua run <scriptname>`

## License

Feel free to use and modify these scripts as needed.