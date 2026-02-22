---
description: Install the shell wrapper for automatic session recovery after project moves/renames
allowed-tools:
  - Read
  - Write
  - Bash
---

# Session Recover Setup

Set up automatic session recovery so `claude --resume` works after moving or renaming a project directory.

## Instructions

1. **Detect the user's shell** by reading `$SHELL`.

2. **Resolve the recovery script path** using `${CLAUDE_PLUGIN_ROOT}`:
   ```
   RECOVER_SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/session-recover.sh"
   ```
   Read this path to confirm it exists.

3. **Check for existing `claude` function or alias** in the target rc file. If one exists, warn the user and ask before overwriting.

4. **Add the shell function** to the appropriate rc file:

   For **bash** (`~/.bashrc`) or **zsh** (`~/.zshrc`):
   ```sh
   # claude-session-recover: auto-recover sessions after project moves
   claude() {
     local session_id=""
     local i=0
     for arg in "$@"; do
       i=$((i + 1))
       case "$arg" in
         --resume=*) session_id="${arg#--resume=}" ;;
         --resume)
           local next=0
           for a2 in "$@"; do
             next=$((next + 1))
             [ "$next" -eq $((i + 1)) ] && session_id="$a2" && break
           done
           ;;
       esac
     done
     if [ -n "$session_id" ]; then
       sh "RECOVER_SCRIPT_PATH" "$session_id" "$(pwd)" 2>/dev/null || true
     fi
     command claude "$@"
   }
   ```
   Replace `RECOVER_SCRIPT_PATH` with the resolved absolute path to `session-recover.sh`.

   For **fish** (`~/.config/fish/functions/claude.fish`):
   ```fish
   # claude-session-recover: auto-recover sessions after project moves
   function claude
     set -l session_id ""
     set -l i 1
     while test $i -le (count $argv)
       switch $argv[$i]
         case '--resume=*'
           set session_id (string replace '--resume=' '' $argv[$i])
         case '--resume'
           set -l next (math $i + 1)
           if test $next -le (count $argv)
             set session_id $argv[$next]
           end
       end
       set i (math $i + 1)
     end
     if test -n "$session_id"
       sh "RECOVER_SCRIPT_PATH" "$session_id" (pwd) 2>/dev/null; or true
     end
     command claude $argv
   end
   ```
   Replace `RECOVER_SCRIPT_PATH` with the resolved absolute path.

5. **Inform the user** to reload their shell:
   - bash/zsh: `source ~/.bashrc` or `source ~/.zshrc`
   - fish: restart terminal or `source ~/.config/fish/functions/claude.fish`

6. **Provide uninstall instructions**: To remove, delete the `claude()` function block (marked with the `# claude-session-recover` comment) from the rc file.
