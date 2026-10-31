# Repository guidance

## Push and CI/CD completion

- When a user asks to push changes, push the requested commit and then monitor the CI/CD run for that exact commit until it finishes.
- Treat the work as complete only after every required job in the run has a successful conclusion. Successful intermediate jobs or an in-progress workflow are not sufficient.
- If a required job fails, inspect the failure, fix it, push the correction, and verify the new run. If an external blocker prevents completion, report the exact remaining status and do not claim the push task is complete.
