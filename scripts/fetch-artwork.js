#!/usr/bin/env node
/**
 * fetch-artwork.js
 * ─────────────────
 * Reads 2026.yaml, fetches missing artwork_url from the iTunes Search API
 * (free, no API key), and writes the URLs back to the file.
 *
 * Usage:
 *   node scripts/fetch-artwork.js
 *
 * Run any time you add new completed albums without artwork_url.
 * Safe to re-run: only fills entries where artwork_url is empty.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dataPath = join(__dirname, '..', 'src', 'data', 'selections', '2026.yaml');

// ── Simple YAML line parser (no external dep needed for this script) ──
// We do targeted string replacement rather than full parse/serialize,
// so the file formatting is preserved exactly.

const raw = readFileSync(dataPath, 'utf8');
const lines = raw.split('\n');

async function fetchArtwork(artist, album) {
  const q = encodeURIComponent(`${artist} ${album}`);
  const url = `https://itunes.apple.com/search?term=${q}&entity=album&limit=5`;
  try {
    const res = await fetch(url);
    const data = await res.json();
    for (const result of data.results ?? []) {
      // Pick highest-res variant (replace 100x100 with 600x600)
      const art = result.artworkUrl100?.replace('100x100bb', '600x600bb');
      if (art) return art;
    }
  } catch (e) {
    console.warn(`  ⚠ iTunes fetch failed for "${album}": ${e.message}`);
  }
  return null;
}

// Find entries: look for blocks starting with "  - week:" and extract
// album/artist/status/artwork_url.
// Strategy: process file as text, find each selection block, check
// if status=completed and artwork_url is empty, then fetch + replace.

const blockRegex = /(\s+- week: \d+[\s\S]*?)(?=\s+- week: \d+|$)/g;

let updated = 0;
let output = raw;

const blocks = [...raw.matchAll(blockRegex)];

for (const match of blocks) {
  const block = match[0];

  const statusMatch = block.match(/status:\s*(\S+)/);
  const artworkMatch = block.match(/artwork_url:\s*["']?([^"'\n]*)["']?/);
  const albumMatch = block.match(/album:\s*["']?([^"'\n]+)["']?/);
  const artistMatch = block.match(/artist:\s*["']?([^"'\n]+)["']?/);
  const weekMatch = block.match(/week:\s*(\d+)/);

  if (!statusMatch || !artworkMatch || !albumMatch || !artistMatch) continue;

  const status = statusMatch[1].trim();
  const artwork = artworkMatch[1].trim();
  const album = albumMatch[1].trim();
  const artist = artistMatch[1].trim();
  const week = weekMatch?.[1] ?? '?';

  if (status !== 'completed') continue;
  if (artwork !== '') continue;
  if (!album || !artist) continue;

  console.log(`Fetching artwork for Week ${week}: ${artist} – ${album}`);
  const artUrl = await fetchArtwork(artist, album);

  if (artUrl) {
    console.log(`  ✓ ${artUrl}`);
    // Replace the empty artwork_url line in this block
    const newBlock = block.replace(
      /artwork_url:\s*["']?["']?/,
      `artwork_url: "${artUrl}"`
    );
    output = output.replace(block, newBlock);
    updated++;
  } else {
    console.log(`  ✗ Not found — skipping`);
  }

  // Be polite to the API
  await new Promise(r => setTimeout(r, 300));
}

if (updated > 0) {
  writeFileSync(dataPath, output, 'utf8');
  console.log(`\n✅ Updated ${updated} artwork URL${updated > 1 ? 's' : ''} in 2026.yaml`);
} else {
  console.log('\n✅ Nothing to update — all completed entries already have artwork.');
}
