# Current Progress

- Done: M1 Move and fight slice code-complete (2026-11-16): leap, glide, flight (touch, PC, gamepad), Volt basic + Chain Lightning + Dash Strike, Spark Drone AI, greybox Downtown, 30-bot load test, Comic and Anime effect styles. 220 tests pass, lint clean, place builds.
- Done: M2 Classes, abilities, enemies code-complete (2026-11-16): 4 class passives, 40 abilities in 5 sets with ranks, mods, capstones and the 52-point budget, POWERS screen, Awakening, 10 team-up combos, 6 humanoid robots with their own AI. 593 tests pass.
- Not yet run in Studio: everything client-side. Studio list in Tasks.md (M1 1 to 22, M2 1 to 15).
- Next: M3 (gear tiers and slots, drops and pity, salvage and upgrade, style collection, saves with migrations, levels and Renown, Credits). Turn off Dev.freeRankCredits once Credits save.
- Repo: local only (/home/user/capeline, branch main). Backup after every milestone: /mnt/project-files/capeline/ (capeline.bundle, Capeline.rbxl, notes). Restore: `git clone capeline.bundle capeline`.
- Tools: rojo, lune, selene, stylua binaries in ~/tools (download from GitHub releases; see roblox-dev-setup memory).
- Auto-resume: a check fires every 90 minutes (send_later) and reschedules itself.
