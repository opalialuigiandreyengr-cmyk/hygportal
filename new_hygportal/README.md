# New HYG Portal

This folder is the rebuild workspace for the new HYG employee portal.

The existing Flask app in `website/` is the reference system and should stay untouched.

## Target Stack

- Mobile app: React Native with Expo
- Backend/database: Supabase
- Auth: Supabase Auth
- Database: Supabase Postgres
- Backend logic: Supabase Edge Functions and/or Postgres RPC functions
- Storage: Supabase Storage

## Main Goal

Build a mobile-first employee portal for a group-of-companies structure:

```text
Group of Companies
  -> Company
      -> Area
          -> Cluster
              -> Store / Branch
                  -> Employees
```

The system must support employee records, transfers, requests, approvals, offset balances, benefits, notifications, and admin controls.

## Project Folders

```text
docs/       Planning, schema, workflow, and migration notes
mobile/     Future Expo React Native app
supabase/   Future Supabase migrations, functions, and seed data
```

