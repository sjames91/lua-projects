CHISPITA EXAMPLE GAMES
======================

Four small coin-op style games, three stages each, built with the Chispita
engine. They use plain shapes only, so they need no sprites, maps or sounds.

  star_dart    STAR DART    side-scrolling space shooter
  pips_peaks   PIP'S PEAKS  micro platformer
  tiny_quest   TINY QUEST   top-down dungeon adventure
  orbit_core   ORBIT CORE   rotational bullet hell

SETTING ONE UP
Make a new microStudio project (one project per game). In its Code tab:
  1. For each chispita_*.txt file in microstudio/chispita/engine, add a
     source file named the same minus ".txt" (e.g. "chispita_sprite") and
     paste the text in. Skip the engine's main.txt.
  2. Add a source file named "arcade" and paste in arcade.txt.
  3. Paste the game's main.txt into the project's "main" file.

ARCADE CONTROLS (all games)
  C        insert coin
  ENTER    start (SPACE works too)
  Each game shows its own controls on the title screen.

Every game has 3 lives, a 10 second continue countdown, a stage intro and
a stage clear screen, and remembers its high score between plays.
Set Arcade.free_play = 1 in init to play without coins.
Set Debug_mode = 1 to see Chispita's debug tools while playing.

HOW THEY'RE BUILT
arcade runs the cabinet side (coins, title screen, lives, stages). Each
game's main only has to define:
  game_init()           make every sprite once
  game_build_stage(n)   set up stage n
  game_respawn()        put the player back after losing a life
  game_update()         one frame of gameplay
  game_draw()           extra drawing (can be empty)
and call arcade_add_score(points), arcade_player_died() and
arcade_stage_clear() at the right moments.

Nothing is ever deleted. Bullets and enemies come from pools
(arcade_make_pool / arcade_take) and are switched off when they're done.
Stage pieces are all built at the start and switched on per stage.

Good things to look at in each:
  STAR DART    kinematic sprites, collision groups, pools, a boss with
               bullet patterns, hit boxes smaller than the drawing
  PIP'S PEAKS  platformer mode, one-way ledges, moving lifts you ride,
               stomping enemies, camera bounds, building levels from helpers
  TINY QUEST   top-down mode, a sword made from a hurt box, knockback,
               keys and doors, enemy behaviours (wander, chase, charge)
  ORBIT CORE   moving with angles (angleToVector), spiral and ring
               patterns, a tiny hit box, grazing, bombs
