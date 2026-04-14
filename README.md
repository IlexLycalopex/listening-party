# Listening Party

52 weeks. 2 brothers. One album from every year 2000–2025.

## Weekly update (2 minutes)

1. Open `src/data/selections/2026.yaml`
2. Find the week you just listened to (search for `week: 17` etc.)
3. Change `status: upcoming` → `status: completed`
4. Fill in `album`, `artist`, and any `links` you have
5. Run artwork fetch (optional — fills in cover art automatically):
   ```bash
   npm run fetch-artwork
   ```
6. Commit and push:
   ```bash
   git add src/data/selections/2026.yaml
   git commit -m "Week 17: Jamie - Bon Iver / For Emma, Forever Ago"
   git push
   ```
7. GitHub Actions deploys automatically — live in ~60 seconds.

## Adding links

For each completed album you can add:
- `wikipedia` — the Wikipedia article URL for the album
- `spotify` — the Spotify album URL (open Spotify → share → copy link)
- `youtube` — the YouTube Music URL

Leave any blank and the icon simply won't appear on the card.

## Running locally

```bash
npm install
npm run dev
# → http://localhost:4322/listening-party
```

## GitHub Pages setup (one-time)

1. Push this repo to GitHub as `listening-party`
2. In your repo → **Settings → Pages → Source**: set to **GitHub Actions**
3. Update `astro.config.mjs`: replace `USERNAME` with your GitHub username
4. Push — Actions will build and deploy automatically

## Changing contributor names / colours

Edit `src/data/contributors.yaml`. The `color` field accepts any CSS colour value.

## Future seasons

To add a 2027 season:
- Add `src/data/selections/2027.yaml` (copy 2026 structure, update `season:` field)
- Add any new contributors to `src/data/contributors.yaml`
- Create `src/pages/2027.astro`
