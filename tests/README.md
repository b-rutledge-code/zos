# tests

Headless harness for the Z-machine. The interpreter lives in
`media/lua/shared/Zos/` and touches no Project Zomboid API, so these run under
a normal Lua interpreter and opcode work is a shell loop instead of a game
restart.

## Running

From the mod root:

```bash
lua tests/run_zork.lua                                  # boot Zork I, stop at the first prompt
lua tests/run_zork.lua --zork2 --status                 # Zork II (Inside the Barrow)
lua tests/run_zork.lua --zork3 --status                 # Zork III (Endless Stair)
lua tests/run_zork.lua --status "open mailbox" "north"
lua tests/test_save.lua
lua tests/test_save_zork2.lua
lua tests/test_save_zork3.lua
lua tests/test_floppies.lua
printf 'open mailbox\nread leaflet\n' | lua tests/run_zork.lua
```

Commands come from the arguments first, then stdin, so the runner is also
usable interactively. `ZOS_SEED` fixes the story's RNG. The runner exits
non-zero on a VM fault (`vm.error`) or if the story runs past its instruction
ceiling, so it works as a CI gate.

## Diffing against a reference interpreter

[mojozork](https://github.com/icculus/mojozork) is a single C file and a good
oracle. Its output has no input echo and it appends its own footer, so
normalise both sides before comparing:

```bash
curl -fsSL -o /tmp/mojozork.c https://raw.githubusercontent.com/icculus/mojozork/main/mojozork.c
cc -O2 -o /tmp/mojozork /tmp/mojozork.c
curl -fsSL -o /tmp/zork1.z3 https://raw.githubusercontent.com/historicalsource/zork1/master/COMPILED/zork1.z3

/tmp/mojozork /tmp/zork1.z3 < cmds.txt \
  | sed 's/^>//' | grep -v '^[[:space:]]*$' \
  | grep -v '^ERROR: EOF' | grep -v 'instructions run$' > /tmp/ref.txt

lua tests/run_zork.lua < cmds.txt \
  | sed 's/^>.*$//' | grep -v '^[[:space:]]*$' \
  | grep -v '^\[[0-9]* instructions executed\]$' > /tmp/mine.txt

diff /tmp/ref.txt /tmp/mine.txt
```

Keep comparison walkthroughs clear of the Troll Room, the thief, and combat:
both interpreters seed their own RNG, so anything random diverges by design.
The house, cellar, gallery/studio chimney route, and the score/inventory verbs
are deterministic and make good corpus.

## Expected baseline

Booting Zork I release 119 prints the banner, `Release 119 / Serial number 880429`,
and the West of House description, then stops at `>` after 407 instructions
with the status line reading `West of House | Score: 0 | Moves: 0`.

Zork II r63 boots to Inside the Barrow. Zork III r25 boots to Endless Stair.
