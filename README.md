# Listening Party

A static website tracking a year-long album listening party. Each week two (or more) contributors alternate album picks, one per year from a defined range. Built with Astro, hosted on GitHub Pages.

**Live site:** https://ilexlycalopex.github.io/listening-party/

---

## Contents

- [Weekly update workflow](#weekly-update-workflow)
- [Editing online via GitHub](#editing-online-via-github)
- [Running locally](#running-locally)
- [Correcting data](#correcting-data)
- [Adding / changing links](#adding--changing-links)
- [Album artwork](#album-artwork)
- [Adding or renaming contributors](#adding-or-renaming-contributors)
- [Adding a future season (2027+)](#adding-a-future-season-2027)
- [Site structure](#site-structure)
- [Deployment](#deployment)

---

## Weekly update workflow

Each week, one entry in the YAML file moves from `upcoming` to `completed`.

1. Open `src/data/selections/2026.yaml`
2. Find the week just completed — search for `week: 17` etc.
3. Make these changes:
   ```yaml
   # Before
   - week: 17
     year_slot: 2008
     contributor: jamie
     album: "For Emma, Forever Ago"
     artist: "Bon Iver"
     status: upcoming        # ← change this
     artwork_url: ""
     links:
       wikipedia: ""
       spotify: ""
       youtube: ""

   # After
   - week: 17
     year_slot: 2008
     contributor: jamie
     album: "For Emma, Forever Ago"
     artist: "Bon Iver"
     status: completed       # ← done
     artwork_url: ""         # filled automatically on deploy
     links:
       wikipedia: ""         # optional — auto-searched if blank
       spotify: ""           # optional — auto-searched if blank
       youtube: ""           # optional — auto-searched if blank
   ```
4. Commit and push:
   ```bash
   git add src/data/selections/2026.yaml
   git commit -m "Week 17: Jamie - Bon Iver / For Emma, Forever Ago"
   git push
   ```
5. GitHub Actions builds and deploys automatically — live in ~60 seconds.

> **Links and artwork are optional.** If left blank, all three links default to a search on Wikipedia / Spotify / YouTube Music, and artwork is fetched automatically from iTunes at build time.

---

## Editing online via GitHub

You don't need a local setup for weekly updates. Edit files directly in the browser:

1. Go to your repo on **github.com**
2. Navigate to `src/data/selections/2026.yaml`
3. Click the **pencil ✏️ icon** (top right of the file view)
4. Make your changes
5. Click **Commit changes** — the site deploys automatically

---

## Running locally

```bash
npm install
npm run dev
# → http://localhost:4322/listening-party/
```

---

## Correcting data

All data lives in `src/data/selections/2026.yaml`. Every field can be edited freely:

| Field | Notes |
|---|---|
| `album` | Album title |
| `artist` | Artist name — must match exactly across entries to group on the Artists page |
| `year_slot` | The year the album represents (used for grouping, not the release year) |
| `contributor` | Must match an `id` in `contributors.yaml` |
| `status` | `completed` = visible on site · `upcoming` = hidden |
| `artwork_url` | Direct image URL. Leave blank to auto-fetch from iTunes on next deploy |
| `links.wikipedia` | Full URL. Leave blank to auto-search |
| `links.spotify` | Full URL. Leave blank to auto-search |
| `links.youtube` | Full URL. Leave blank to auto-search |
| `notes` | Free text — shown on the card (e.g. "also considered: X") |

To **force artwork to re-fetch** for an entry, clear its `artwork_url` field and push — the build script will refill it.

---

## Adding / changing links

Paste the full URL into the relevant field:

```yaml
links:
  wikipedia: "https://en.wikipedia.org/wiki/For_Emma,_Forever_Ago"
  spotify: "https://open.spotify.com/album/0oqch00EbeHrdVHOEVVVZo"
  youtube: "https://music.youtube.com/browse/MPREb_xxxxxx"
```

To get a Spotify link: open the album in Spotify → **⋯ → Share → Copy link to album**.

If a field is left blank, the link falls back to a search for that album — so the button still works, it just lands on search results rather than the exact page.

---

## Album artwork

Artwork is fetched automatically from the iTunes Search API every time the site builds. You don't need to do anything.

- If `artwork_url` is already filled, the existing URL is used.
- If it's blank and the album is `completed`, the build script finds and saves the URL.

To run the artwork fetch manually (e.g. to preview locally with artwork):

```bash
npm run fetch-artwork
```

---

## Adding or renaming contributors

Edit `src/data/contributors.yaml`:

```yaml
- id: jamie       # used in selections YAML — do not change after entries exist
  name: Jamie     # display name — safe to change any time
  color: "#e8a87c"  # any CSS colour

- id: nick
  name: Nick
  color: "#7ca8e8"

- id: chris       # ready for 2027
  name: Chris
  color: "#7ce8a8"
```

**Important:** the `id` field links contributors to their picks in the selections YAML. If you change an `id`, you must also update every matching `contributor:` line in the selections files.

The `color` appears as a dot on album cards, in the nav bar, and on contributor profile pages. Any CSS colour works (`#hex`, `rgb()`, `hsl()`, named colours).

---

## Adding a future season (2027+)

### Step 1 — Create the selections file

Copy `src/data/selections/2026.yaml` to `src/data/selections/2027.yaml` and update the header:

```yaml
season: 2027
title: "Listening Party 2027"
description: "3 contributors. Working backwards from 1999."
total_weeks: 52   # adjust if different

selections:
  - week: 1
    year_slot: 1999
    contributor: jamie
    album: ""
    artist: ""
    status: upcoming
    artwork_url: ""
    links:
      wikipedia: ""
      spotify: ""
      youtube: ""
    notes: ""
  # ... etc
```

### Step 2 — Register the season

Edit `src/data/seasons.yaml` — add the new season and optionally mark 2026 as complete:

```yaml
- id: "2026"
  title: "Listening Party 2026"
  description: "52 weeks. 2 brothers. One album from every year 2000–2025."
  contributors: [jamie, nick]
  status: complete        # ← change from "active" when 2026 is done

- id: "2027"
  title: "Listening Party 2027"
  description: "3 contributors. Working backwards from 1999."
  contributors: [jamie, nick, chris]
  status: active          # ← this makes 2027 the new home page
```

The home page automatically shows the **last** `status: active` season in this list. No code changes needed.

### Step 3 — Add any new contributors

Add them to `src/data/contributors.yaml` (see above). Chris is already defined — just update the name/colour if needed.

### Step 4 — Push

```bash
git add .
git commit -m "Add 2027 season"
git push
```

The nav bar gains a **2027** tab, the home page switches to 2027, and the 2026 season remains accessible at `/listening-party/2026/`.

---

## Site structure

```
src/
├── data/
│   ├── contributors.yaml          ← names, colours, IDs
│   ├── seasons.yaml               ← season registry (controls home page)
│   └── selections/
│       └── 2026.yaml              ← all 52 weekly picks for 2026
├── pages/
│   ├── index.astro                ← home page (renders latest active season)
│   ├── [season].astro             ← e.g. /2026/, /2027/
│   ├── contributors/
│   │   └── [id].astro             ← e.g. /contributors/jamie/
│   └── artists/
│       ├── index.astro            ← /artists/ — all artists
│       └── [slug].astro           ← e.g. /artists/joanna-newsom/
├── components/
│   ├── AlbumCard.astro
│   ├── ProgressBar.astro
│   └── SiteNav.astro
├── layouts/
│   └── Base.astro
└── styles/
    └── global.css
```

---

## Deployment

The site deploys automatically via GitHub Actions on every push to `main`. No manual steps needed after initial setup.

**Initial setup (one-time):**
1. Push repo to GitHub as `listening-party`
2. Go to repo → **Settings → Pages → Source** → set to **GitHub Actions**
3. Push any change — the first deploy runs automatically

**To trigger a manual deploy** (e.g. to refresh artwork without a data change):
- Go to repo → **Actions** → select the workflow → **Run workflow**
