#!/usr/bin/env node
/**
 * fetch-artwork.js
 * ─────────────────
 * Scans every season file in src/data/selections/, fetches missing
 * artwork_url values from the iTunes Search API (free, no API key),
 * and writes the URLs back to the files.
 *
 * Usage:
 *   node scripts/fetch-artwork.js
 *
 * Run any time you add new completed albums without artwork_url.
 * Safe to re-run: only fills entries where artwork_url is empty.
 *
 * Entries are identified by parsing the YAML properly (js-yaml), but the
 * write-back is a targeted line edit so comments and formatting are
 * preserved exactly.
 */

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import yaml from 'js-yaml';

const __dirname = dirname(fileURLToPath(import.meta.url));
const selectionsDir = join(__dirname, '..', 'src', 'data', 'selections');

async function fetchArtwork(artist, album) {
  const q = encodeURIComponent(`${artist} ${album}`);
  const url = `https://itunes.apple.com/search?term=${q}&entity=album&limit=5`;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url);
      if (!res.ok) {
        console.warn(`  ⚠ iTunes API returned HTTP ${res.status} for "${album}" (attempt ${attempt}/3)`);
        if (attempt < 3) await new Promise(r => setTimeout(r, attempt * 2000));
        continue;
      }
      const data = await res.json();
      for (const result of data.results ?? []) {
        // Pick highest-res variant (replace 100x100 with 600x600)
        const art = result.artworkUrl100?.replace('100x100bb', '600x600bb');
        if (art) return art;
      }
      console.warn(`  ⚠ iTunes returned 0 results for "${artist} – ${album}"`);
      return null;
    } catch (e) {
      console.warn(`  ⚠ iTunes fetch failed for "${album}" (attempt ${attempt}/3): ${e.message}`);
      if (attempt < 3) await new Promise(r => setTimeout(r, attempt * 2000));
    }
  }
  return null;
}

/**
 * Replace the empty artwork_url line inside the `- week: N` entry.
 * Mutates `lines` in place; returns true if a line was replaced.
 */
function setArtworkUrl(lines, week, url) {
  const startRe = new RegExp(`^\\s*- week:\\s*${week}\\b`);
  const start = lines.findIndex(l => startRe.test(l));
  if (start === -1) return false;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^\s*- week:/.test(lines[i])) break; // ran into the next entry
    const m = lines[i].match(/^(\s*)artwork_url:/);
    if (m) {
      lines[i] = `${m[1]}artwork_url: "${url}"`;
      return true;
    }
  }
  return false;
}

let totalUpdated = 0;
const files = readdirSync(selectionsDir).filter(f => f.endsWith('.yaml')).sort();

for (const file of files) {
  const filePath = join(selectionsDir, file);
  const raw = readFileSync(filePath, 'utf8');

  let doc;
  try {
    doc = yaml.load(raw);
  } catch (e) {
    console.error(`✗ ${file}: invalid YAML — ${e.message}`);
    process.exitCode = 1;
    continue;
  }

  const needing = (doc?.selections ?? []).filter(
    s => s.status === 'completed' && !s.artwork_url && s.album && s.artist
  );
  if (needing.length === 0) continue;

  console.log(`\n${file}:`);
  const lines = raw.split('\n');
  let updated = 0;

  for (const sel of needing) {
    console.log(`Fetching artwork for Week ${sel.week}: ${sel.artist} – ${sel.album}`);
    const artUrl = await fetchArtwork(sel.artist, sel.album);

    if (artUrl) {
      if (setArtworkUrl(lines, sel.week, artUrl)) {
        console.log(`  ✓ ${artUrl}`);
        updated++;
      } else {
        console.warn(`  ⚠ Could not locate artwork_url line for week ${sel.week} — skipping`);
      }
    } else {
      console.log(`  ✗ Not found — skipping`);
    }

    // Be polite to the API
    await new Promise(r => setTimeout(r, 300));
  }

  if (updated > 0) {
    writeFileSync(filePath, lines.join('\n'), 'utf8');
    console.log(`✅ Updated ${updated} artwork URL${updated > 1 ? 's' : ''} in ${file}`);
    totalUpdated += updated;
  }
}

if (totalUpdated === 0) {
  console.log('\n✅ Nothing to update — all completed entries already have artwork.');
}
