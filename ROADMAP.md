# Eden Music Analyzer Roadmap

## Operating Procedure

- You will be invoked repeatadly and given this prompt, you will either execute or review one work item on each iteration, log your work and commit to git.
- Follow this procedure precicely.

### Statuses

- ⚪ - pending, ready for work
- 🟠 - in progress
- 🔵 - ready for review
- 🟢 - done

### Workflow

⚪ -> 🟠 -> 🔵 -> 🟢

### Steps

#### 1. Select the next task

1) Select the first 🔵 if exists.
2) Else, Select the first 🟠 if exists.
3) Else, Select the first ⚪ if exists
4) Else, no more tasks

#### 2. Update your context

1) Look at the latest git commits relevant to this task and see what was changed.
2) Look at any pending changes that were not yet commited.
3) Look at the relevant worklog entries to see what was done.

**note**: if the selected task status is ⚪, the context would likely be empty

#### 3. Work

- If 🔵:
  1. Code / Documentation analysis in a sub agent with a fresh context window.
  2. If applicable simulate / test the feature.
  3. Update the task status. Failed -> 🟠 , Passed -> 🟢
- If 🟠 or ⚪:
  1. Execute the task
  2. Update the task status -> 🔵

#### 4. Report

1) append an entry to the worklog summarizing your work, so the next session would know the progress.
  Format:
  - If 🟠 or ⚪:
    `- [Task #{taskid}] {what was done}`
  - If 🔵:  
    `- [Task #{taskid}] ✅`
    or
    `- [Task #{taskid}] ❌ - {issues description}`
2) commit.


## Tasks

1. [🟢] - Create the roadmap.
2. [🟢] - Create the initial implementation.
3. [🔵] - Split the @README.md into 3 files INSTALL.md, TROUBLESHOOTING.md, the main README should refer to these new files, but focus on how to run (when already
installed), how to tune, and Output Reference (what the reciever of the OSC messages needs)
4. [⚪] - 

