Capeline art upload package (built by art/upload/make_package.py in the repo). Nothing here contains a key.

1. Unzip or copy this whole folder anywhere in Documents (for example Documents\capeline-upload-2). Not the ApexMMA folder.
2. Double-click upload.bat. It reads Documents\roblox-keys\capeline-key.txt (line 1 key, line 2 your user id),
   uploads each image in files\ as a Decal on your account (not for sale, not listed anywhere) and writes
   ids.json and resolve_ids.txt in this folder. It never prints or saves the key.
   If any say FAILED at the end, double-click it again: it only retries the missing ones.
3. In Studio (any place), open View > Command Bar, paste all of resolve_ids.txt and press Enter. When it prints
   "Capeline ids done", it opens Workspace > CapelineImageIds: select all of its text and save it as image_ids.txt
   in this folder.
4. Attach ids.json and image_ids.txt in the Capeline chat. They hold only asset ids. Claude puts every id in the
   game, tests and builds.
