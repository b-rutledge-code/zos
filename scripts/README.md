# Scripts

Development and deployment scripts for ZOS. This folder is **gitignored**
(except this README) so machine-specific paths stay out of the repo.

## What's here

- **deploy.sh** – copies `Contents/mods/ZOS/` into `~/Zomboid/mods/ZOS/` for local testing. Run from project root: `./scripts/deploy.sh`.

Reproducible tooling lives in `tools/` instead, tracked in the repo:
`tools/bake_zork.sh 1|2|3` regenerates the baked Zork I/II/III story files.
