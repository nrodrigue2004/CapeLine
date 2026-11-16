# Current Progress

- Done: M1 Move and fight slice code-complete (2026-11-16): leap, glide, flight (touch, PC, gamepad), Volt basic + Chain Lightning + Dash Strike, Spark Drone AI, greybox Downtown, 30-bot load test, Comic and Anime effect styles. 220 tests pass, lint clean, place builds.
- Not yet run in Studio: everything client-side. Studio list in Tasks.md (M1 items 1 to 22).
- Next: M2 (4 classes with passives, 5 sets incl. Blade, 40 abilities in both styles, super slot, Awakening, ranks and mods, power budget, 6 enemies).
- Repo: local only (/home/user/capeline, branch main). Backup after every milestone: /mnt/project-files/capeline/ (capeline.bundle, Capeline.rbxl, notes). Restore: `git clone capeline.bundle capeline`.
- Tools: rojo, lune, selene, stylua binaries in ~/tools (download from GitHub releases; see roblox-dev-setup memory).
- Auto-resume: a check fires every 90 minutes (send_later) and reschedules itself.
