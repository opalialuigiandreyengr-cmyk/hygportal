-- Migration 0165: Badges & Awarded Badges Tables and RLS Policies for Supabase

-- 1. Create Badges Catalog Table
CREATE TABLE IF NOT EXISTS public.badges (
  id TEXT PRIMARY KEY DEFAULT 'bdg_' || extract(epoch from now())::bigint || '_' || floor(random() * 1000)::text,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'Milestones',
  icon_data TEXT NOT NULL DEFAULT 'star',
  custom_image_path TEXT,
  icon_bg_color TEXT NOT NULL DEFAULT '#FEF3C7',
  icon_color TEXT NOT NULL DEFAULT '#D97706',
  points INT NOT NULL DEFAULT 100,
  awarded_count INT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'Active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Create Awarded Badges History Table
CREATE TABLE IF NOT EXISTS public.awarded_badges (
  id TEXT PRIMARY KEY DEFAULT 'awd_' || extract(epoch from now())::bigint || '_' || floor(random() * 1000)::text,
  badge_id TEXT REFERENCES public.badges(id) ON DELETE CASCADE,
  badge_title TEXT NOT NULL,
  badge_icon TEXT NOT NULL DEFAULT 'star',
  custom_image_path TEXT,
  badge_icon_bg_color TEXT NOT NULL DEFAULT '#FEF3C7',
  badge_icon_color TEXT NOT NULL DEFAULT '#D97706',
  employee_id TEXT,
  employee_name TEXT NOT NULL,
  employee_department TEXT NOT NULL DEFAULT 'General',
  employee_avatar_color TEXT NOT NULL DEFAULT '#2563EB',
  employee_photo_url TEXT,
  awarded_by TEXT NOT NULL DEFAULT 'Super Admin',
  awarded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  note TEXT NOT NULL DEFAULT '',
  points_awarded INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.awarded_badges ADD COLUMN IF NOT EXISTS employee_photo_url TEXT;

-- 3. Enable Row Level Security (RLS) & Grant Access
ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.awarded_badges ENABLE ROW LEVEL SECURITY;

GRANT ALL ON public.badges TO authenticated;
GRANT ALL ON public.badges TO anon;
GRANT ALL ON public.badges TO service_role;

GRANT ALL ON public.awarded_badges TO authenticated;
GRANT ALL ON public.awarded_badges TO anon;
GRANT ALL ON public.awarded_badges TO service_role;

-- 4. RLS Policies
DROP POLICY IF EXISTS "Public select badges" ON public.badges;
CREATE POLICY "Public select badges" ON public.badges FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public insert badges" ON public.badges;
CREATE POLICY "Public insert badges" ON public.badges FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Public update badges" ON public.badges;
CREATE POLICY "Public update badges" ON public.badges FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Public delete badges" ON public.badges;
CREATE POLICY "Public delete badges" ON public.badges FOR DELETE USING (true);

DROP POLICY IF EXISTS "Public select awarded_badges" ON public.awarded_badges;
CREATE POLICY "Public select awarded_badges" ON public.awarded_badges FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public insert awarded_badges" ON public.awarded_badges;
CREATE POLICY "Public insert awarded_badges" ON public.awarded_badges FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Public update awarded_badges" ON public.awarded_badges;
CREATE POLICY "Public update awarded_badges" ON public.awarded_badges FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Public delete awarded_badges" ON public.awarded_badges;
CREATE POLICY "Public delete awarded_badges" ON public.awarded_badges FOR DELETE USING (true);

-- 5. Helper Function to Increment Badge Awarded Count
CREATE OR REPLACE FUNCTION public.increment_badge_awarded_count(p_badge_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.badges
  SET awarded_count = awarded_count + 1,
      updated_at = NOW()
  WHERE id = p_badge_id;
END;
$$;

-- 6. Helper Function to Award Multiple Badges to an Employee in 1 Transaction
CREATE OR REPLACE FUNCTION public.award_multiple_badges_to_employee(
  p_employee_id TEXT,
  p_employee_name TEXT,
  p_employee_department TEXT,
  p_employee_avatar_color TEXT,
  p_awarded_by TEXT,
  p_note TEXT,
  p_badge_ids TEXT[],
  p_employee_photo_url TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_badge RECORD;
BEGIN
  FOR v_badge IN
    SELECT * FROM public.badges WHERE id = ANY(p_badge_ids)
  LOOP
    INSERT INTO public.awarded_badges (
      id, badge_id, badge_title, badge_icon, custom_image_path,
      badge_icon_bg_color, badge_icon_color, employee_id, employee_name,
      employee_department, employee_avatar_color, employee_photo_url, awarded_by, awarded_at,
      note, points_awarded
    )
    VALUES (
      'awd_' || extract(epoch from now())::bigint || '_' || floor(random() * 1000)::text,
      v_badge.id, v_badge.title, v_badge.icon_data, v_badge.custom_image_path,
      v_badge.icon_bg_color, v_badge.icon_color, p_employee_id, p_employee_name,
      p_employee_department, p_employee_avatar_color, p_employee_photo_url, p_awarded_by, NOW(),
      COALESCE(p_note, ''), v_badge.points
    );

    UPDATE public.badges
    SET awarded_count = awarded_count + 1,
        updated_at = NOW()
    WHERE id = v_badge.id;
  END LOOP;
END;
$$;

-- 7. Optional Seed Badges (Uncomment if default template badges are desired)
/*
INSERT INTO public.badges (id, title, description, category, icon_data, icon_bg_color, icon_color, points, awarded_count)
VALUES
  ('bdg_001', 'Early Adopter', 'Joined within first 6 months of portal launch', 'Milestones', 'rocket_launch', '#FFF7ED', '#EA580C', 200, 34),
  ('bdg_002', 'Top Performer', 'Ranked #1 in quarterly performance evaluation', 'Performance', 'emoji_events', '#FEF3C7', '#D97706', 500, 12),
  ('bdg_003', 'Learning Champion', 'Completed 10+ internal training modules & courses', 'Learning & Skills', 'menu_book', '#EFF6FF', '#2563EB', 300, 27),
  ('bdg_004', '5-Year Veteran', 'Celebrated 5 years of dedicated company service', 'Milestones', 'workspace_premium', '#FAF5FF', '#9333EA', 1000, 8),
  ('bdg_005', 'Culture Champion', 'Demonstrated outstanding teamwork & core values', 'Values & Culture', 'favorite', '#FFE4E6', '#E11D48', 250, 19),
  ('bdg_006', 'Perfect Attendance', '100% on-time attendance for the quarter', 'Attendance', 'verified', '#ECFDF5', '#059669', 150, 45),
  ('bdg_007', 'Innovation Pioneer', 'Submitted a winning process improvement proposal', 'Performance', 'lightbulb_outline', '#FEF9C3', '#CA8A04', 400, 6),
  ('bdg_008', 'Customer Hero', 'Received top 5-star commendations from clients', 'Performance', 'star', '#FEF3C7', '#D97706', 350, 15)
ON CONFLICT (id) DO NOTHING;

-- 7. Optional Seed Awarded History Records
INSERT INTO public.awarded_badges (id, badge_id, badge_title, badge_icon, badge_icon_bg_color, badge_icon_color, employee_id, employee_name, employee_department, employee_avatar_color, awarded_by, note, points_awarded)
VALUES
  ('awd_101', 'bdg_002', 'Top Performer', 'emoji_events', '#FEF3C7', '#D97706', 'emp_01', 'Maria Santos', 'Human Resources', '#2563EB', 'Super Admin', 'Outstanding execution on Q3 onboarding program.', 500),
  ('awd_102', 'bdg_001', 'Early Adopter', 'rocket_launch', '#FFF7ED', '#EA580C', 'emp_02', 'Juan Dela Cruz', 'Information Technology', '#059669', 'System Auto-Trigger', 'Portal account activated within launch window.', 200),
  ('awd_103', 'bdg_003', 'Learning Champion', 'menu_book', '#EFF6FF', '#2563EB', 'emp_03', 'Ana Reyes', 'Finance & Accounting', '#9333EA', 'HR Manager', 'Completed advanced Excel & compliance training.', 300),
  ('awd_104', 'bdg_006', 'Perfect Attendance', 'verified', '#ECFDF5', '#059669', 'emp_04', 'Carlos Mendoza', 'Operations', '#D97706', 'Super Admin', 'Zero tardiness or absences for Q2.', 150)
ON CONFLICT (id) DO NOTHING;
*/
