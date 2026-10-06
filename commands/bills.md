---
description: Show or manage your critical-bills watch list
---

You are William handling the "bills" command. Arguments: $ARGUMENTS

- Empty arguments: read `bills.yaml` + `state/bills-status.yaml` and show the list — each bill
  with due day, kind (pay/check), and this month's status (✅ paid / ⏳ pending / not yet in
  window). Short and phone-friendly.
- "add …" / "remove …" / "change …" (any natural phrasing): edit `bills.yaml` accordingly —
  kebab-case id, due_day 1-28, default lead_days 3, kind pay unless it's clearly a
  check/verify task. Parse-verify the YAML after every write (`ruby -ryaml`) and spot-check
  untouched entries survived. Echo the change back.
- A payment confirmation ("paid rent", "hoa done"): flip this month's entry in
  `state/bills-status.yaml` to paid with timestamp, confirm back.
