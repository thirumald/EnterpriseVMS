import { useEffect, useState } from "react";

export interface Clip { src: string; poster?: string; title?: string; credit?: string }

const base = import.meta.env.BASE_URL;
export const mediaUrl = (path: string) => base + path.replace(/^\//, "");

let cached: Promise<Clip[]> | null = null;

/** Real footage is described in public/media/manifest.json. Empty or missing → the app falls back to simulated feeds. */
export function loadClips(): Promise<Clip[]> {
  cached ??= fetch(mediaUrl("media/manifest.json"))
    .then((r) => (r.ok ? r.json() : { clips: [] }))
    .then((m: { clips?: Clip[] }) => (Array.isArray(m.clips) ? m.clips : []))
    .catch(() => []);
  return cached;
}

export function useClips(): Clip[] {
  const [clips, setClips] = useState<Clip[]>([]);
  useEffect(() => { let live = true; void loadClips().then((c) => live && setClips(c)); return () => { live = false; }; }, []);
  return clips;
}

const hash = (s: string) => { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619); return h >>> 0; };

/** Deterministic clip + start offset per camera so neighbouring tiles never look identical. */
export function clipFor(id: string, clips: Clip[]): { clip: Clip; seed: number } | undefined {
  if (!clips.length) return undefined;
  const seed = hash(id);
  return { clip: clips[seed % clips.length], seed };
}
