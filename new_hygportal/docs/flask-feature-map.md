# Flask Feature Map

The existing Flask app remains the reference system. Do not delete or overwrite it.

## Model Mapping

```text
Flask User
-> Supabase Auth + user_profiles

Flask Employee
-> employees + employee_assignments

Flask Company
-> companies

Flask Department
-> departments / functions

Flask EsarfRequest
-> requests + time_request_details

Flask LeaveRequest
-> requests + leave_request_details

Flask DiscountRequest
-> requests + benefit_request_details later

Flask ProductChargeRequest
-> requests + benefit_request_details later

Flask EsarfApprover
-> authority_assignments

Flask LeaveApprover
-> authority_assignments

Flask PerkApprover
-> authority_assignments or special_permissions later

Flask Notification
-> notifications

Flask MobileSession
-> Supabase Auth sessions
```

## Features To Preserve

```text
Employee login and registration
Employee dashboard
Employee profile
Profile completion
Overtime / ESARF filing
Offset earn/use
Leave filing
Employee discount
Employee charge credit
Approver request management
Employee request history
Notifications
Admin employee management
Company and department management
Reports
Mobile API behavior
```

## Features To Improve

```text
Approval logic becomes reusable through approval steps
Approvers are based on level + function + scope
Transfers are handled through assignment history
Missing approvers escalate automatically
IT, Payroll, Finance, Store, and Operations permissions stay separate
Request history shows exact approver steps
Supabase Auth replaces custom session handling
```

## Old Approval Limitation

The Flask app uses separate approver concepts:

```text
EsarfApprover
LeaveApprover
PerkApprover
```

This becomes hard to maintain for many companies and stores.

The new system uses:

```text
authority_assignments
approval_level_routes
request_approval_steps
```

That makes approval behavior consistent across overtime, offset, leave, and future benefits.

