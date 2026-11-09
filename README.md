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
- **Two sections:** switch between **Guild** (everyone at once) and **Goons** (one goon's journey) in the window's header.
- **Latest:** a guild activity feed, newest first and grouped by day: dings, deaths, first boss kills, epics, silly milestones and rank-ups, so you see what happened while you were offline. Click an entry to open that goon.
- **Leaderboards:** most deaths, biggest yapper, critter murderer, most travelled and more. Click a name to open that goon.
- **Guild death map:** every goon's deaths on one map, zone by zone, with the zone's deadliest killer. Hover a skull to see who died, to what and at what level; click it to open their journey.
- **Guild quest log:** every quest a goon has picked up, grouped into collapsible areas (zone, quest count, how many are in progress, level range), with who's on it now, who has completed it and who dropped it. Filter by status (in progress, completed, dropped), by goon, or to quests near your level; sort by level, name or most goons; or search by quest or zone. Quests you finished before installing the addon are filled in once a guildie picks them up.
- **Guild news pop-ups:** cards slide in when a goon dings, dies, gets a first boss kill or an epic, unlocks a silly milestone or ranks up. Click one to open their journey.
- **Race to 60:** a chart of everyone's level against hours played, plus "fastest to level 10/20/.../60" cards.
- **Weekly recap:** your first login each week shows last week's highlights: levels gained, deaths, MVP, death of the week, biggest jumper and more.
- **Gooner Score and ranks:** points for every milestone, from *Gooner Initiate* up to *Grand Gooner*.
- **GOONER ZONE DETECTED:** when a goon walks into the Lion's Pride Inn in Goldshire, the whole guild gets a flashing alert with a raid-warning sound. Visits are counted, with milestones up to *Lives In Goldshire Inn*.
- **Hall of Fame:** one-off shout-outs that ship with a release. Each new entry pops up once for every goon, with a fanfare, the first time they log in on that version. All entries stay in **Guild → Hall of Fame**. The first one is the *Hall of Thanes*.
- **Update nudge:** if a guildie has a newer version, you get told, and an "Update" button appears with the download link.

### Install
1. Download the latest `GoonerJourneys-x.y.z.zip` from the [Releases page](../../releases). For a test build, use the **Actions** tab → latest run → **Artifacts**.
2. Unzip it into your WoW Forever `Interface/AddOns/` folder, so you end up with `Interface/AddOns/GoonerJourneys/GoonerJourneys.toc`.
3. Restart the game or `/reload`.

Do **not** use GitHub's green "Download ZIP" button. It gives the folder the wrong name and WoW won't load it.

### Usage
- Click the minimap button or type `/gooner` (also `/gj` or `/journey`).
- The **Reload** button in the window's header (or `/gooner reload`) does a `/reload`, handy after installing an update.
- Right-click the minimap button to toggle guildies on the world map.
- `/gooner sync`: ask online guildies for any data you're missing (it also happens automatically every few minutes).
- `/gooner status`: show what's been sent and received, and from whom. Use this first if a guildie isn't showing up.
- `/gooner recap`: show this week's recap so far.
- `/gooner versions`: see who's on which addon version. `/gooner update` shows the download link.
- `/gooner news`: turn the guild news pop-ups on or off.
- `/gooner announce`: also post your own news in guild chat (off by default).
- **Middle-click the world map** to ping that spot for the guild. Guildies see a pulsing marker with your name for 30 seconds, plus a chat line and a ping sound. `/gooner pings` turns receiving them on or off.
- `/gooner alerts`: turn the GOONER ZONE alerts on or off.
- `/gooner fame`: show the latest Hall of Fame entry again.
- `/gooner weekly`: turn the weekly recap on login on or off.
- `/gooner interval 30`: change how often your trail is sampled (5-300 seconds).
- `/gooner minimap`: hide or show the minimap button.

### How sharing works
WoW addons can't use the internet, so there's no server. Each member's addon stores everyone's journeys and swaps updates over the guild's hidden addon channel:
- While you're online together, updates arrive within seconds.
- When you log in, the addon tells the guild what it already has, and anyone online fills in the gaps. You'll get someone's progress even if they're offline, as long as somebody who saw it is online.
- Every few minutes the addons compare notes again, so any gaps fill in without anyone typing a command.
- Some players' games don't receive guild addon messages from certain guildies. The addon spots this, by asking over the guild channel and getting no answer, and then also whispers its data straight to that player. You don't need to do anything.
- Only members running the addon get tracked.

### For developers
- `GoonerJourneys/`: the addon itself (Lua, Interface `16001`, game type `camelot`).
- `tests/`: an offline simulation that loads the addon with a mocked WoW API and checks guild sync between three fake players. Run it with `pip install lupa && python tests/run_tests.py`.
- `scripts/package.sh [version]`: builds `dist/GoonerJourneys-<version>.zip`.
- CI builds and tests every push.
- **To publish a release:** go to **Actions** → **Build addon zip** → **Run workflow**, pick `main`, enter a version such as `0.2.0` and run it. GitHub creates the `v0.2.0` tag and a Release with the zip attached. Pushing a `v*` tag yourself does the same thing.

### Adding a Hall of Fame entry
1. Add an entry at the top of `GJ.HALL_OF_FAME` in `GoonerJourneys/HallOfFame.lua` with a new unique `id`, a title, the goons' names and a short text.
2. Optional photo: run `python scripts/make_photo.py screenshot.jpg GoonerJourneys/media/<name>.tga`, then set `image = "Interface\\AddOns\\GoonerJourneys\\media\\<name>"` on the entry.
3. Merge and release. Everyone sees it once, on their first login with the new version.
