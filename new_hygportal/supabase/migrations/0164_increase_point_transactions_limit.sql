-- Migration 0164: Set point transactions log limit to 100
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
