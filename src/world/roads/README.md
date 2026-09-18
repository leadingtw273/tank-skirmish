# Road texture derivatives

`assets/AtomicRealmModularRoads` preserves upstream bytes exactly. Some upstream files are PSD payloads incorrectly named `.png`, so Godot cannot import them as PNG. Run `scripts/roads/prepare_texture_derivatives.py` to decode only those payloads with ffmpeg into `generated/textures/` and write `texture_derivatives.json`.

The JSON maps the original `res://` path to its valid derived PNG. Builders must consult it before using a texture. The original source files are never renamed, converted, or overwritten.

For each detected false `.png`, the preparer additionally writes a same-name `.import` sidecar with `importer="skip"`. Godot supports this mode to avoid reimporting the PSD payload; existing editor cache errors may still require an editor rescan.
