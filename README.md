# guild-addons
Addons for our guild on WoW Forever - Unregistered Hypercam Users

## The Gooner Journeys

A Muddy Boots-style journey tracker for the whole guild. Every goon with the addon records their journey, and the addon shares it with everyone else in the guild automatically.

**What it tracks**
- **Timeline:** level milestones every 5 levels (with /played at the time), first time in every zone, dungeon and raid, first boss kills, profession milestones, first rare, epic and legendary gear, and every death (who or what killed you, and where).
- **Silly milestones:** *Humiliated By Wildlife*, *Gravity Check*, *Bunny Hopper*, *Professional Yapper*, *Ding... Dead*, *Touch Grass Warning*, *Walked To Mordor (Wrong Game)*, *Naked And Afraid* and about 40 more.
- **Stats:** deaths, killing blows, critters murdered, quests, dungeon runs, bosses, wipes, miles travelled, flights, hearths, jumps, dances, hugs, guild chat messages, gold earned, /played and professions.
- **Gear:** a snapshot of each member's equipped gear, viewable even when they're offline. Hover for tooltips, shift-click to link.
- **Journey map:** a trail of everywhere they've walked (sampled every 30s), with skulls where they died, plus their live position.
- **World map:** online goons show up live on your normal world map.
- **Leaderboards:** most deaths, biggest yapper, critter murderer, most travelled and more.

### Install
1. Download the latest `GoonerJourneys-x.y.z.zip` from the [Releases page](../../releases). For a test build, use the **Actions** tab → latest run → **Artifacts**.
2. Unzip it into your WoW Forever `Interface/AddOns/` folder, so you end up with `Interface/AddOns/GoonerJourneys/GoonerJourneys.toc`.
3. Restart the game or `/reload`.

Do **not** use GitHub's green "Download ZIP" button. It gives the folder the wrong name and WoW won't load it.

### Usage
- Click the minimap button or type `/gooner` (also `/gj` or `/journey`).
- Right-click the minimap button to toggle guildies on the world map.
- `/gooner sync`: ask online guildies for any data you're missing.
- `/gooner interval 30`: change how often your trail is sampled (5-300 seconds).
- `/gooner minimap`: hide or show the minimap button.

### How sharing works
WoW addons can't use the internet, so there's no server. Each member's addon stores everyone's journeys and swaps updates over the guild's hidden addon channel:
- While you're online together, updates arrive within seconds.
- When you log in, the addon tells the guild what it already has, and anyone online fills in the gaps. You'll get someone's progress even if they're offline, as long as somebody who saw it is online.
- Only members running the addon get tracked.

### For developers
- `GoonerJourneys/`: the addon itself (Lua, Interface `16001`, game type `camelot`).
- `tests/`: an offline simulation that loads the addon with a mocked WoW API and checks guild sync between three fake players. Run it with `pip install lupa && python tests/run_tests.py`.
- `scripts/package.sh [version]`: builds `dist/GoonerJourneys-<version>.zip`.
- CI builds and tests every push.
- **To publish a release:** go to **Actions** → **Build addon zip** → **Run workflow**, pick `main`, enter a version such as `0.2.0` and run it. GitHub creates the `v0.2.0` tag and a Release with the zip attached. Pushing a `v*` tag yourself does the same thing.
