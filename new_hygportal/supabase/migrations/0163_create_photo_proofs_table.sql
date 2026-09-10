-- Create photo_proofs table for tracking employee photo proof submissions
CREATE TABLE IF NOT EXISTS public.photo_proofs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  employee_name TEXT NOT NULL,
  store_name TEXT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  time_digits TEXT NOT NULL,
  time_period TEXT NOT NULL,
  date_formatted TEXT NOT NULL,
  day_formatted TEXT NOT NULL,
  location_text TEXT NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  drive_file_id TEXT,
  drive_web_view_link TEXT,
  photo_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.photo_proofs ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read photo proof records
CREATE POLICY "Allow authenticated read photo_proofs"
  ON public.photo_proofs FOR SELECT
  TO authenticated
  USING (true);

-- Allow authenticated users to insert photo proof records
CREATE POLICY "Allow authenticated insert photo_proofs"
  ON public.photo_proofs FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow public read access for photo_proofs if needed
CREATE POLICY "Allow anon read photo_proofs"
  ON public.photo_proofs FOR SELECT
  TO anon
  USING (true);

-- Allow anon insert for offline / guest photo proofs
CREATE POLICY "Allow anon insert photo_proofs"
  ON public.photo_proofs FOR INSERT
  TO anon
  WITH CHECK (true);
