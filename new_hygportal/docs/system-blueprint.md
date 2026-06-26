# System Blueprint

## Core Principle

The new portal separates rank, domain, and territory:

```text
Level = authority rank
Function = permission domain
Scope = where authority applies
```

Examples:

```text
Store Manager
- Level: 2
- Function: Operations
- Scope: Store

Cluster Manager
- Level: 4
- Function: Operations
- Scope: Cluster

Payroll Officer
- Level: 1
- Function: Payroll
- Scope: Company
```

This prevents IT, Payroll, Finance, Store, and Operations employees from accidentally sharing permissions just because they have similar authority levels.

## Authority Levels

```text
Level 1 - Crew, Assistant Manager, IT Staff, Payroll Officer, Maintenance Staff,
          Logistic Driver/Checker, Supervisor, Purchaser
Level 2 - Store Manager
Level 3 - Department Manager
Level 4 - Cluster Manager
Level 5 - Area Manager
Level 6 - Operations Manager
Level 7 - Operations Director
Level 8 - General Manager, Finance Director
```

More positions can be added later without changing the approval engine.

## Request Types For MVP

```text
Overtime     = 2 approvers
Offset Earn  = 2 approvers
Use Offset   = 1 approver + offset credit validation
Leave        = 1 approver
```

Benefits can be added after MVP:

```text
Employee Discount
Employee Charge / Credit
```

## Main Modules

### Employee Mobile App

```text
Home
Requests
Approvals
Profile
Notifications
```

### Admin / HR Web Panel

```text
Dashboard
Employees
Organization
Assignments
Authority Assignments
Requests
Reports
Settings
```

The mobile app is the priority, but admin workflows should be designed from the start because HR controls the organization data.

