-- Safe to apply through the Neon SQL Editor or by the EF migration runner.
-- This is the SQL equivalent of EF migration 20261005100000_PlaylistCover.
ALTER TABLE public.playlists
    ADD COLUMN IF NOT EXISTS cover_url TEXT NULL;
