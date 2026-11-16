# Team Workflow

How nate and his partner work on Capeline at the same time (nate, 2026-11-16).

## Where the code lives
- The GitHub repo `nrodrigue2004/Capeline` is the one true copy. Claude pushes every change there; you both pull from it.
- Until that repo exists, the code is only in Claude's workspace and the backup in project files, and a partner cannot get updates.

## One-time setup (each person)
1. Install Git, Roblox Studio and Rokit (github.com/rojo-rbx/rokit). If PowerShell says `rokit` is not recognized, run `$env:Path += ";$env:USERPROFILE\.rokit\bin"` (or add that folder to your user PATH once).
2. Use a normal PowerShell window, not Administrator.
3. `git clone https://github.com/nrodrigue2004/Capeline.git`, then `cd Capeline`, then `rokit install` (Rojo 7.4.4 and the other tools from rokit.toml), then `rojo plugin install`, then restart Studio.

## Every session
1. `git pull`
2. `rojo serve`, then in Studio: Plugins > Rojo > Connect.
3. Edit code in `src`, never scripts inside Studio (Rojo overwrites them).
4. Done: `git add -A`, `git commit -m "what you changed"`, `git pull`, `git push`.

## Rules
- In a shared Team Create place, only one person connects Rojo at a time.
- Always pull before you start and before you push.
- A merge conflict: stop and ask nate (or Claude).
- Uploading meshes, sounds or images to Roblox needs nate's account.
- Read CLAUDE.md and notes/Current Progress.md first.
