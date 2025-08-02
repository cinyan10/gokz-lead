# GOKZ Replay Lead Bot

A plugin that enables a replay bot to guide players ("lead") during gameplay on a GOKZ server.

[![Video of the Plugin](https://img.youtube.com/vi/rh_xXcjZENM/0.jpg)](https://www.youtube.com/watch?v=rh_xXcjZENM)

## Features

- Automatically plays a replay bot when players join the server (similar to KZTimer behavior)
- Players can use `!lead` to toggle a guiding bot that shows the route
- Distance-based auto pause/resume
- Move the bot to the closest replay tick to the player
- Automatically selects the best replay based on the shortest tick count with course 0

## Commands

- `!lead [stop distance] [start distance]`: How far away from you the bot will stop and start
  - Default: `!lead` → `stop distance = 500`, `start distance = 200`  

## Requirements

- A modified GOKZ Replays plugin that exposes additional natives used by this plugin
- Replay files stored under:  
  `addons/sourcemod/data/gokz-replays/_runs/<mapname>/`

## Installation

1. Upload both `gokz-lead` and your modified `gokz-replays` plugin to `addons/sourcemod/plugins/`
2. Ensure valid replay files exist in the replay directory

## Notes

- Currently, only one player can use the lead bot at a time

## To-Do

- Check whether the player can see the bot (line-of-sight)
- Support multiple players using lead bots simultaneously  
  - Use bot names to identify and kick them after use
- Add player preferences for pause/resume distance
- Add a ConVar to toggle automatic bot playback on map start (like KZTimer)
- Restart when player start timer, and end lead when player end timer
