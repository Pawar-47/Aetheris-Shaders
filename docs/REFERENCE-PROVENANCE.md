# Reference-source provenance and preservation

This project uses two external references supplied or identified during development. They
are inputs for inspection, not source trees to modify or silently absorb.

## User-supplied Shader.zip

- Identified as **MakeUp – Ultra Fast v9.6**.
- SHA-256: `f49d9a9245bcdee742bba97c7d5001a3b4fcf43d501d672e3645b57637b9db4a`
- The archive was opened and read only. It was not edited, renamed, repacked, committed to
  GitHub, or included in the Aetheris CI artifact.
- The archive itself contains no LICENSE file. The upstream
  [MakeUpUltraFast repository](https://github.com/javiergcim/MakeUpUltraFast) has an
  LGPL-3.0 licence at the inspected revision.
- No MakeUp GLSL source file is copied into Aetheris. The archive is used to study
  high-level approaches such as bounded reflection marches, depth-gated light shafts,
  sample-budget choices, reduced-resolution bloom and the cost of disabling whole effects.
  Aetheris' implementations are authored in its own codebase. Any future direct source
  port must be reviewed for licence compatibility and attribution before it is used.

## Public shader template

- Repository: [ascpixi/minecraft-shader-template](https://github.com/ascpixi/minecraft-shader-template)
- Inspected ref: `master`, commit
  `ab2b99c9e1715cb951936157fe3c2ef94890233b`.
- It was consulted for Iris 1.21.5 / GLSL 330 program layout and build conventions only.
- No files were edited in that repository, no commits or pull requests were made there, and
  no source files from it are copied into Aetheris. Its root had no LICENSE file at the
  inspected revision, so it is treated strictly as a read-only reference.

## Project boundary

All implementation work is confined to
`Pawar-47/Aetheris-Shaders`, branch `perf/full-feature-performance`. The default
`main` branch and published v1.6.1 tag are not changed. The user ZIP, public template,
and CI artifact are kept separate. No companion resource pack or PBR pack is required.
