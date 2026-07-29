# MVP Scope

## Build First

```text
1. Supabase database schema
2. Supabase Auth integration
3. Employee records
4. Company -> Area -> Cluster -> Store structure
5. Employee assignments
6. Authority assignments
7. Overtime request
8. Offset earn request
9. Use offset request
10. Leave request
11. Approval inbox
12. Approve/reject flow
13. Notifications
```

## Defer To Version 2

```text
Employee discount
Employee charge credit
Reports
AI assistant
Profile edit approval workflow
Advanced dashboard analytics
Document uploads
Full migration tooling from Flask database
```

## Mobile App Screens For MVP

```text
Login
Home
My Requests
New Request
Request Detail
Approvals Inbox
Approval Detail
Profile
Notifications
```

## Admin Features Needed For MVP

These can be built as a simple admin web panel later, or as protected mobile/admin screens at first.

```text
Manage companies
Manage areas
Manage clusters
Manage stores
Manage employees
Assign employee to store/cluster/area/company
Assign authority to approvers
View all requests
Manual admin fallback queue
```

## First Technical Milestone

Create the initial Supabase SQL migration:

```text
organization tables
employee tables
assignment tables
request config tables
request tables
approval step tables
offset balance tables
notification tables
seed functions, request types, and approval routes
```

