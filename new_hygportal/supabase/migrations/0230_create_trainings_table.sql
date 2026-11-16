-- Migration 0230: Create Trainings Table for Rewards System
CREATE TABLE IF NOT EXISTS public.trainings (
  id TEXT PRIMARY KEY DEFAULT 'trn_' || extract(epoch from now())::bigint || '_' || floor(random() * 1000)::text,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  training_date DATE NOT NULL,
  start_time TEXT NOT NULL DEFAULT '09:00',
  end_time TEXT NOT NULL DEFAULT '12:00',
  location TEXT NOT NULL DEFAULT '',
  trainer TEXT NOT NULL DEFAULT '',
  badge_id TEXT REFERENCES public.badges(id) ON DELETE SET NULL,
  badge_title TEXT DEFAULT '',
  badge_icon TEXT DEFAULT 'star',
  badge_icon_bg_color TEXT DEFAULT '#FEF3C7',
  badge_icon_color TEXT DEFAULT '#D97706',
  badge_points INT DEFAULT 0,
  attendees JSONB NOT NULL DEFAULT '[]'::jsonb,
  status TEXT NOT NULL DEFAULT 'Upcoming', -- 'Upcoming', 'Concluded', 'Cancelled'
  is_badges_awarded BOOLEAN NOT NULL DEFAULT false,
  created_by TEXT NOT NULL DEFAULT 'Super Admin',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for querying trainings by date and status
CREATE INDEX IF NOT EXISTS idx_trainings_date ON public.trainings(training_date DESC);
CREATE INDEX IF NOT EXISTS idx_trainings_status ON public.trainings(status);

-- Enable Row Level Security (RLS)
ALTER TABLE public.trainings ENABLE ROW LEVEL SECURITY;

GRANT ALL ON public.trainings TO authenticated;
GRANT ALL ON public.trainings TO anon;
GRANT ALL ON public.trainings TO service_role;

DROP POLICY IF EXISTS "Public select trainings" ON public.trainings;
CREATE POLICY "Public select trainings" ON public.trainings FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public insert trainings" ON public.trainings;
CREATE POLICY "Public insert trainings" ON public.trainings FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Public update trainings" ON public.trainings;
CREATE POLICY "Public update trainings" ON public.trainings FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Public delete trainings" ON public.trainings;
CREATE POLICY "Public delete trainings" ON public.trainings FOR DELETE USING (true);
