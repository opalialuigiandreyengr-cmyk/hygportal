-- Migration 0155: Rewards management schema & RPC functions

CREATE TABLE IF NOT EXISTS public.rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_name TEXT NOT NULL,
  stocks INTEGER NOT NULL DEFAULT 0,
  points_value INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'Active',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS
ALTER TABLE public.rewards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read access to authenticated users"
  ON public.rewards FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Allow all access to admin users"
  ON public.rewards FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.user_profiles up
      WHERE up.auth_user_id = auth.uid()
        AND up.app_role IN ('admin', 'hr', 'super_admin')
    )
  );

-- RPC 1: Fetch all rewards
CREATE OR REPLACE FUNCTION public.admin_get_rewards()
RETURNS TABLE (
  id UUID,
  product_name TEXT,
  stocks INTEGER,
  points_value INTEGER,
  status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT r.id, r.product_name, r.stocks, r.points_value, r.status, r.created_at, r.updated_at
  FROM public.rewards r
  ORDER BY r.created_at DESC;
END;
$$;

-- RPC 2: Create reward
CREATE OR REPLACE FUNCTION public.admin_create_reward(
  p_product_name TEXT,
  p_stocks INTEGER,
  p_points_value INTEGER,
  p_status TEXT DEFAULT 'Active'
)
RETURNS TABLE (
  id UUID,
  product_name TEXT,
  stocks INTEGER,
  points_value INTEGER,
  status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_id UUID;
BEGIN
  INSERT INTO public.rewards (product_name, stocks, points_value, status)
  VALUES (TRIM(p_product_name), GREATEST(0, p_stocks), GREATEST(0, p_points_value), COALESCE(p_status, 'Active'))
  RETURNING public.rewards.id INTO v_new_id;

  RETURN QUERY
  SELECT r.id, r.product_name, r.stocks, r.points_value, r.status, r.created_at, r.updated_at
  FROM public.rewards r
  WHERE r.id = v_new_id;
END;
$$;

-- RPC 3: Update reward
CREATE OR REPLACE FUNCTION public.admin_update_reward(
  p_reward_id UUID,
  p_product_name TEXT,
  p_stocks INTEGER,
  p_points_value INTEGER,
  p_status TEXT DEFAULT 'Active'
)
RETURNS TABLE (
  id UUID,
  product_name TEXT,
  stocks INTEGER,
  points_value INTEGER,
  status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.rewards
  SET product_name = TRIM(p_product_name),
      stocks = GREATEST(0, p_stocks),
      points_value = GREATEST(0, p_points_value),
      status = COALESCE(p_status, 'Active'),
      updated_at = NOW()
  WHERE public.rewards.id = p_reward_id;

  RETURN QUERY
  SELECT r.id, r.product_name, r.stocks, r.points_value, r.status, r.created_at, r.updated_at
  FROM public.rewards r
  WHERE r.id = p_reward_id;
END;
$$;

-- RPC 4: Delete reward
CREATE OR REPLACE FUNCTION public.admin_delete_reward(
  p_reward_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.rewards WHERE id = p_reward_id;
  RETURN true;
END;
$$;
