# tmux-asc-binder

## Problem Statement
The `agent-status-collector` tool (found at ../agent-status-collector) gathers and centralizes local AI agent statuses for a developer, but does not bring that information into the foreground without manually querying via the tool and formating the information in a meaningful way.

## Proposal
We want to wrap the `agent-status-collector` and bind it into tmux to use in our configuration file for status bar / window label rendering, as well as add some optional functions that can be bound for the user.

### Design Philosophy
- TPM compatibility: for simplicity, people may want to install this way, so make it an option.
- Non-opinionated: we're not going to force anything onto the user. The user can disable every single feature easily.
- Scoped & Isolated: use of scoped (asc_*) user-options at the global level allow every user-impacting option to be turned on or off.
- No default output: when installed, nothing will be added to the user's status bar or window label. Every pane, window, and session will be updated with scoped user-options to identify the highest-priority agent status within that scope. The user has full control to use those within their configuration.

### Features
- Scoped agent status: every pane with an agent will have an assortment of user-options added. These will bubble up, with the most pressing priority overriding in the case where multiple agents run in the same Window or Session.
- Status Icons: in addition to general status types, a configurable status icon user-option will be set for each pane/window/session, which can be used to quickly render an icon.
- Jump to Agent: a script is added and bound to a configurable key, which will open an fzf pane, with preview, which allows the user to fuzzy search for an agent and jump to a selected one. If it is a different session, the current session will switch, in addition to switching Window and Pane accordingly. This entire binding will be excluded if flagged off via a global user-option.

