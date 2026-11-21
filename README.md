# Lua Projects

Games and game engines written in Lua: LÖVE games, plus microStudio projects in microScript (a Lua-like language).

## Highlights

- **[Chispita Engine](microstudio/chispita)** is a 2D game engine for [microStudio](https://microstudio.dev), written in microScript ([use it in microStudio](https://microstudio.io/i/Sjamescalaway/chispita/)). It covers sprites, physics, collisions, tile maps, a camera, timers, tweens and a debug mode, and it comes with [full documentation](microstudio/chispita/CHISPITA_DOCS.txt).
- **[Lower Orbit](microstudio/shmup)** is a ship game in progress, built on Chispita Engine. Its flight model takes each ship's mass and drag from the ship's shape, and the pilot can get out and walk around. [▶ Play it](https://microstudio.io/Sjamescalaway/day1thegameplayloopdrawing/JE4B894V/) · [Design docs](microstudio/shmup/design_docs)
- **[ALL HANDS](love2d/all_hands)** is a four-player split-screen prototype in LÖVE: one ship, four crew, and nobody can run the ship from where they are standing.

## Folders

- [`microstudio/`](microstudio) has Chispita, Shmup, and [four small example games](microstudio/games) built on Chispita.
- [`love2d/`](love2d) has games made with [LÖVE](https://love2d.org), including the earlier Lua version of the engine.

## License

Free and open source. Code is under the [MIT License](LICENSE). Written content and docs are under [CC BY-SA 4.0](LICENSE-CONTENT.md).
