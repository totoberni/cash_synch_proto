# /status — Check Orchestrator Status

Read and display the current state of the orchestration system.

## Steps
1. Read `.orchestrator/state.md` — display current phase and status
2. Read `.orchestrator/task-queue.md` — count queued/delegated/done/blocked tasks
3. Read `.orchestrator/active-tasks.md` — show any running workers
4. Summarize: "Phase N: [status]. X/Y tasks complete. Z workers active. Next: [description]."

## If issues detected
- Stale active tasks (worker listed but no PID running) → flag as potentially crashed
- Blocked tasks where blocker is resolved → flag as ready to unblock
- Human gates pending → remind what the human needs to do
