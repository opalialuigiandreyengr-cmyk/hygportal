-- Migration 0163: Admin Points Management RLS Policies & RPC functions

-- Drop restrictive unique index on (user_profile_id, source) if exists to allow multiple transactions per user
DROP INDEX IF EXISTS public.idx_user_hyg_point_transactions_profile_source;

-- 1. Grant direct table access to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_hyg_point_accounts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_hyg_point_transactions TO authenticated;

-- 2. Allow authenticated users/admins to read all point accounts
DROP POLICY IF EXISTS "Admins can read all HYG point accounts" ON public.user_hyg_point_accounts;
CREATE POLICY "Admins can read all HYG point accounts"
ON public.user_hyg_point_accounts FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Admins can update all HYG point accounts" ON public.user_hyg_point_accounts;
CREATE POLICY "Admins can update all HYG point accounts"
ON public.user_hyg_point_accounts FOR UPDATE
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Admins can insert HYG point accounts" ON public.user_hyg_point_accounts;
CREATE POLICY "Admins can insert HYG point accounts"
ON public.user_hyg_point_accounts FOR INSERT
TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "Admins can read all HYG point transactions" ON public.user_hyg_point_transactions;
CREATE POLICY "Admins can read all HYG point transactions"
ON public.user_hyg_point_transactions FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Admins can insert HYG point transactions" ON public.user_hyg_point_transactions;
CREATE POLICY "Admins can insert HYG point transactions"
ON public.user_hyg_point_transactions FOR INSERT
TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "Admins can delete HYG point transactions" ON public.user_hyg_point_transactions;
CREATE POLICY "Admins can delete HYG point transactions"
ON public.user_hyg_point_transactions FOR DELETE
TO authenticated
USING (true);

-- RPC to delete point transaction bypassing RLS
CREATE OR REPLACE FUNCTION public.admin_delete_point_transaction(
  p_tx_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.user_hyg_point_transactions
  WHERE id = p_tx_id;
  RETURN FOUND;
END;
$$;

-- 3. RPC to fetch point accounts bypassing RLS
CREATE OR REPLACE FUNCTION public.admin_get_point_accounts()
RETURNS TABLE (
  id UUID,
  user_profile_id UUID,
  auth_user_id UUID,
  employee_id UUID,
  balance NUMERIC,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  employee_name TEXT,
  employee_email TEXT,
  department_name TEXT,
  position_name TEXT,
  company_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    a.id,
    a.user_profile_id,
    a.auth_user_id,
    a.employee_id,
    a.balance,
    a.created_at,
    a.updated_at,
    COALESCE(
      TRIM(CONCAT_WS(' ', e.first_name, e.last_name)),
      p.display_name,
      'Employee'
    )::TEXT AS employee_name,
    COALESCE(e.email, p.email, '')::TEXT AS employee_email,
    COALESCE(d.name, e.department, 'General')::TEXT AS department_name,
    COALESCE(pos.title, 'STAFF')::TEXT AS position_name,
    COALESCE(c.name, 'HYG Corporate')::TEXT AS company_name
  FROM public.user_hyg_point_accounts a
  LEFT JOIN public.user_profiles p ON p.id = a.user_profile_id
  LEFT JOIN public.employees e ON e.id = a.employee_id
  LEFT JOIN public.departments d ON d.id = e.department_id
  LEFT JOIN public.positions pos ON pos.id = e.position_id
  LEFT JOIN public.companies c ON c.id = e.company_id
  ORDER BY a.balance DESC, a.updated_at DESC;
END;
$$;

-- 4. RPC to adjust points balance
CREATE OR REPLACE FUNCTION public.admin_adjust_points(
  p_account_id UUID,
  p_points_delta NUMERIC,
  p_reason TEXT DEFAULT 'Administrative adjustment'
)
RETURNS TABLE (
  id UUID,
  balance NUMERIC,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec public.user_hyg_point_accounts%ROWTYPE;
  v_new_balance NUMERIC;
BEGIN
  SELECT * INTO v_rec FROM public.user_hyg_point_accounts WHERE id = p_account_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Point account % not found.', p_account_id;
  END IF;

  v_new_balance := GREATEST(0, v_rec.balance + p_points_delta);

  UPDATE public.user_hyg_point_accounts
  SET balance = v_new_balance,
      updated_at = NOW()
  WHERE id = p_account_id;

  INSERT INTO public.user_hyg_point_transactions (
    account_id,
    user_profile_id,
    auth_user_id,
    employee_id,
    source,
    points,
    status,
    note
  ) VALUES (
    v_rec.id,
    v_rec.user_profile_id,
    v_rec.auth_user_id,
    v_rec.employee_id,
    CASE WHEN p_points_delta >= 0 THEN 'Admin Award' ELSE 'Admin Deduction' END,
    ABS(p_points_delta),
    'released',
    p_reason
  );

  RETURN QUERY
  SELECT a.id, a.balance, a.updated_at
  FROM public.user_hyg_point_accounts a
  WHERE a.id = p_account_id;
END;
$$;

-- 5. RPC to fetch point transactions log with status
CREATE OR REPLACE FUNCTION public.admin_get_point_transactions()
RETURNS TABLE (
  id TEXT,
  employee TEXT,
  type TEXT,
  points TEXT,
  status TEXT,
  reason TEXT,
  date TEXT,
  performedBy TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id::TEXT,
    COALESCE(
      TRIM(CONCAT_WS(' ', e.first_name, e.last_name)),
      p.display_name,
      'Employee'
    )::TEXT AS employee,
    CASE WHEN t.points >= 0 THEN 'Awarded' ELSE 'Deducted' END::TEXT AS type,
    CONCAT(CASE WHEN t.points >= 0 THEN '+' ELSE '-' END, t.points::INT, ' Pts')::TEXT AS points,
    COALESCE(t.status, 'released')::TEXT AS status,
    COALESCE(t.note, t.source, '-')::TEXT AS reason,
    TO_CHAR(t.created_at, 'YYYY-MM-DD HH24:MI')::TEXT AS date,
    'HR Admin'::TEXT AS performedBy
  FROM public.user_hyg_point_transactions t
  LEFT JOIN public.user_profiles p ON p.id = t.user_profile_id
  LEFT JOIN public.employees e ON e.id = t.employee_id
  ORDER BY t.created_at DESC
  LIMIT 100;
END;
$$;

-- 6. RPC to bulk award points to all accounts
CREATE OR REPLACE FUNCTION public.admin_bulk_award_points(
  p_points_delta NUMERIC,
  p_reason TEXT DEFAULT 'Bulk Administrative Award'
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  IF p_points_delta <= 0 THEN
    RAISE EXCEPTION 'Points delta must be positive.';
  END IF;

  -- Update all existing accounts
  UPDATE public.user_hyg_point_accounts
  SET balance = balance + p_points_delta,
      updated_at = NOW();

  -- Insert a single summary transaction log for the bulk award action
  INSERT INTO public.user_hyg_point_transactions (
    source,
    points,
    status,
    note
  )
  VALUES (
    'Bulk HR Award',
    p_points_delta,
    'released',
    p_reason
  );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
