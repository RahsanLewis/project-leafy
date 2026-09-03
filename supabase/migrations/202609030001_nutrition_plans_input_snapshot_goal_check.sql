-- Table-level contract for nutrition_plans.input_snapshot.goal.
-- persist_nutrition_plan already casts profiles.goal to public.weight_goal;
-- this CHECK makes the same requirement a documented table contract, not an
-- incidental side effect of that insert.
--
-- PostgreSQL CHECK treats UNKNOWN as pass. {"goal": null} has the key, so
-- `? 'goal'` is true, `->>'goal'` is SQL NULL, and `NULL IN (...)` is UNKNOWN.
-- coalesce(..., false) rejects that row. Key presence alone is not enough.
--
-- ADD ... NOT VALID then VALIDATE so a future environment with bad rows fails
-- closed at VALIDATE rather than locking writes during ADD.
-- Rollback: alter table public.nutrition_plans drop constraint nutrition_plans_input_snapshot_goal_check;

alter table public.nutrition_plans
  add constraint nutrition_plans_input_snapshot_goal_check
  check (
    input_snapshot ? 'goal'
    and coalesce(input_snapshot->>'goal' in ('lose', 'maintain', 'gain'), false)
  )
  not valid;

alter table public.nutrition_plans
  validate constraint nutrition_plans_input_snapshot_goal_check;
