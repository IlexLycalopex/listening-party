import yaml from 'js-yaml';
import { z } from 'astro/zod';

// All YAML is pulled in through Vite at build time (no node:fs, no cwd
// guessing) and validated with zod, so a typo in a weekly edit fails the
// build with a pointed error instead of silently hiding an album.

// ── Schemas ───────────────────────────────────────────────────────
// YAML renders an empty value (`notes:`) as null — coerce those to ''.
const looseString = z.preprocess(v => v ?? '', z.string());

const contributorSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  color: z.string().min(1),
});

const seasonMetaSchema = z.object({
  id: z.union([z.string(), z.number()]).transform(String),
  title: z.string(),
  description: z.string(),
  contributors: z.array(z.string()).default([]),
  status: z.string(),
});

const linksSchema = z.object({
  wikipedia: looseString.optional(),
  spotify: looseString.optional(),
  youtube: looseString.optional(),
});

const selectionSchema = z
  .object({
    week: z.number().int().min(1),
    year_slot: z.number().int(),
    contributor: z.string().min(1),
    album: looseString,
    artist: looseString,
    status: z.enum(['completed', 'upcoming']),
    artwork_url: looseString.optional(),
    links: linksSchema.optional(),
    notes: looseString.optional(),
  })
  .superRefine((sel, ctx) => {
    if (sel.status === 'completed' && (!sel.album.trim() || !sel.artist.trim())) {
      ctx.addIssue({
        code: 'custom',
        message: `week ${sel.week} is completed but is missing album and/or artist`,
      });
    }
  });

const seasonFileSchema = z.object({
  season: z.union([z.string(), z.number()]).transform(String),
  title: z.string(),
  description: z.string(),
  total_weeks: z.number().int().min(1),
  selections: z.array(selectionSchema),
});

// ── Types ─────────────────────────────────────────────────────────
export type Contributor = z.output<typeof contributorSchema>;
export type SeasonMeta = z.output<typeof seasonMetaSchema>;
export type Selection = z.output<typeof selectionSchema> & { season: string };

export interface Season {
  id: string;
  title: string;
  description: string;
  total_weeks: number;
  selections: Selection[];
}

// ── Loading ───────────────────────────────────────────────────────
function parseYaml<S extends z.ZodTypeAny>(schema: S, raw: string, label: string): z.output<S> {
  let data: unknown;
  try {
    data = yaml.load(raw);
  } catch (e) {
    throw new Error(`${label}: invalid YAML — ${(e as Error).message}`);
  }
  const result = schema.safeParse(data);
  if (!result.success) {
    const issues = result.error.issues
      .map(i => `  • ${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('\n');
    throw new Error(`${label} failed validation:\n${issues}`);
  }
  return result.data;
}

const contributorsRaw = import.meta.glob('../data/contributors.yaml', {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>;

const seasonsRaw = import.meta.glob('../data/seasons.yaml', {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>;

const selectionFilesRaw = import.meta.glob('../data/selections/*.yaml', {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>;

const contributors: Contributor[] = parseYaml(
  z.array(contributorSchema),
  Object.values(contributorsRaw)[0]!,
  'contributors.yaml'
);

const seasonsIndex: SeasonMeta[] = parseYaml(
  z.array(seasonMetaSchema),
  Object.values(seasonsRaw)[0]!,
  'seasons.yaml'
);

const knownContributors = new Set(contributors.map(c => c.id));

const seasons: Season[] = Object.entries(selectionFilesRaw)
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([path, raw]) => {
    const fileName = path.split('/').pop()!;
    const id = fileName.replace('.yaml', '');
    const parsed = parseYaml(seasonFileSchema, raw, `selections/${fileName}`);

    const seenWeeks = new Set<number>();
    for (const sel of parsed.selections) {
      if (seenWeeks.has(sel.week)) {
        throw new Error(`selections/${fileName}: duplicate week ${sel.week}`);
      }
      seenWeeks.add(sel.week);
      if (!knownContributors.has(sel.contributor)) {
        throw new Error(
          `selections/${fileName}: week ${sel.week} references unknown contributor "${sel.contributor}"`
        );
      }
    }

    return {
      id,
      title: parsed.title,
      description: parsed.description,
      total_weeks: parsed.total_weeks,
      selections: parsed.selections.map(s => ({ ...s, season: id })),
    };
  });

// ── Loaders ───────────────────────────────────────────────────────
export function loadContributors(): Contributor[] {
  return contributors;
}

export function loadSeasonsIndex(): SeasonMeta[] {
  return seasonsIndex;
}

export function loadSeason(year: string): Season {
  const season = seasons.find(s => s.id === year);
  if (!season) throw new Error(`No season data file for "${year}" in src/data/selections/`);
  return season;
}

export function loadAllSeasons(): Season[] {
  return seasons;
}

export function loadAllSelections(): Selection[] {
  return seasons.flatMap(s => s.selections);
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
