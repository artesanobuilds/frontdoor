# Guide: critical bills

`bills.yaml` (`bills:`): `id, name, due_day (1-28), kind: pay|check, lead_days, note`.
`state/bills-status.yaml` (`months:`): `bill_id, month, status: pending|paid, paid_at`.

## The loop
- When `today >= due_day - lead_days`, open this month's entry as `pending` and say so in the
  digest: one line per bill, grouped, not one message per bill.
- On the due day and not paid: a direct ping, once. After the due day: daily, in the digest only,
  with "overdue N days". Three overdue days → ask whether it is handled elsewhere, then stop.
- "paid X" / "hoa done" flips the entry to `paid` with a timestamp. Confirm back in five words.
- A payment confirmation found at the source (a bank or lender email) counts as paid; say where
  you saw it.

## Rules from calibrations
- **The lender's date beats bills.yaml.** If a statement says the 22nd and the file says the
  20th, update the file and say so.
- **A cluster opening at once** is one message, ranked by date, not five.
- **One-off money requests are not bills.** A school fee or a reimbursement request lives in
  `todo.md` or a reminder; this file is for recurring obligations only.
- **Never quote a figure you have not seen this month.** An old balance restated as current has
  caused real alarm. Say "last seen $X on <date>" or say nothing.
- Tone follows the owner's state. Pressure is a tactic, not a default.
