import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import yaml from 'js-yaml';

// In dev, import.meta.url points to the source file → relative path works.
// In CI build, compiled chunks land in dist/.prerender/ → fall back to process.cwd().
function resolveDataDir(): string {
  const relPath = join(dirname(fileURLToPath(import.meta.url)), '..', 'data');
  if (existsSync(relPath)) return relPath;
  return join(process.cwd(), 'src', 'data');
}
const dataDir = resolveDataDir();

// ── Types ─────────────────────────────────────────────────────────
export interface Contributor {
  id: string;
  name: string;
  color: string;
}

export interface Season {
  id: string;
  title: string;
  description: string;
  total_weeks: number;
  selections: Selection[];
}

export interface Selection {
  week: number;
  year_slot: number;
  contributor: string;
  album: string;
  artist: string;
  status: 'completed' | 'upcoming';
  artwork_url?: string;
  links?: { wikipedia?: string; spotify?: string; youtube?: string };
  notes?: string;
  season?: string; // injected after loading
}

// ── Loaders ───────────────────────────────────────────────────────
export function loadContributors(): Contributor[] {
  const raw = readFileSync(join(dataDir, 'contributors.yaml'), 'utf8');
  return yaml.load(raw) as Contributor[];
}

export function loadSeason(year: string): Season {
  const raw = readFileSync(join(dataDir, 'selections', `${year}.yaml`), 'utf8');
  const season = yaml.load(raw) as Season;
  season.id = year;
  // Inject season id into each selection
  for (const s of season.selections) s.season = year;
  return season;
}

export function loadAllSeasons(): Season[] {
  const files = readdirSync(join(dataDir, 'selections'))
    .filter(f => f.endsWith('.yaml'))
    .sort();
  return files.map(f => loadSeason(f.replace('.yaml', '')));
}

export function loadAllSelections(): Selection[] {
  return loadAllSeasons().flatMap(s => s.selections);
}

// ── Helpers ───────────────────────────────────────────────────────
export function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/['']/g, '')       // smart apostrophes
    .replace(/[^a-z0-9\s-]/g, ' ')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

export function getContribMap(contributors: Contributor[]): Record<string, Contributor> {
  return Object.fromEntries(contributors.map(c => [c.id, c]));
}

/** All unique artists who have at least one completed pick, across all seasons */
export function getAllArtists(selections: Selection[]): string[] {
  const set = new Set(
    selections
      .filter(s => s.status === 'completed' && s.artist)
      .map(s => s.artist)
  );
  return [...set].sort((a, b) => a.localeCompare(b));
}
