# Super Playmat

A procedural, animated playmat that covers all 32 Magic color identities with **one shader and no textures or video**. Everything is computed on the GPU each frame from a 5-color palette plus a few "personality" sliders.

| File | What it is |
|---|---|
| `scripts/playmat/super_playmat.gdshader` | The `canvas_item` shader (domain-warped noise, plus the color layers) |
| `scripts/playmat/mana_palette.gd` | `ManaPalette`: the 32 identities, their names, palettes and traits |
| `scripts/playmat/super_playmat.gd` | `SuperPlaymat`: attach it to a `ColorRect`; it handles the material, animation and transitions |
| `scripts/playmat/playmat_demo.gd` + `scenes/playmat_demo.tscn` | A test bench for trying the mats |

## Try it

Open `scenes/playmat_demo.tscn` and press **F6** (Run Current Scene).

| Key | Action |
|---|---|
| ← / → | Cycle your identity (bottom half) |
| ↑ / ↓ | Cycle the opponent's identity (top half) |
| R | Random matchup |
| Space | Damage pulse on your mat |
| Q | Quality: Low / Medium / High |
| P | Pause the animation |
| S | Switch between a split board and a single mat |

## How each color looks

| Color | Personality layer |
|---|---|
| White | Radiant light rays from the center |
| Blue | Flowing caustic ripples |
| Black | A "breathing" void that darkens the mat, with a faint rim glow |
| Red | Rising embers and heat; faster animation |
| Green | A living network of veins (animated Voronoi) |
| Colorless | Iridescent shimmer over crystal facets in silver |

Multicolor identities blend their colors into a 5-stop gradient and mix their layers. Each layer is weighted by 1/√n, so a 5-color mat still shows every effect clearly instead of washing them out.

## Scene setup (step by step)

### A. Split board (two players)

```
Table (Control)                      ← your existing table root
└── Playmats (VBoxContainer)         full rect, Mouse Filter = Ignore, separation = 0
    ├── OpponentMat (ColorRect)      script: super_playmat.gd
    │                                Size Flags ▸ Vertical = Expand+Fill
    │                                identity = "UBR", flip = ✔, seam_glow = 0.6
    └── PlayerMat (ColorRect)        script: super_playmat.gd
                                     Size Flags ▸ Vertical = Expand+Fill
                                     identity = "WG", seam_glow = 0.6
└── … cards, hands, life totals …    keep these BELOW Playmats in the tree so they draw on top
```

1. In your table scene, add a **VBoxContainer** named `Playmats` as the **first child**, so it draws behind everything else.
2. Click **Layout ▸ Full Rect**. In the Inspector, set **Mouse ▸ Filter = Ignore** and **Theme Overrides ▸ Constants ▸ Separation = 0**.
3. Add two **ColorRect** children, `OpponentMat` and `PlayerMat`. For each one, set **Size Flags ▸ Vertical** to **Expand** (plus Fill).
4. Drag `scripts/playmat/super_playmat.gd` onto each ColorRect. **Leave Material empty**: the script creates its own material.
5. Set `identity` in the Inspector. Because the script is a `@tool`, the mat renders live in the editor. On `OpponentMat`, tick **Flip** so its effects face the opponent. Set **Seam Glow** to about 0.6 on both mats so the center line glows.

### B. Single shared mat

Add one **ColorRect** as the first child, set **Layout ▸ Full Rect**, and attach `super_playmat.gd`. That's all.

### C. Behind a camera that pans or zooms

If the table moves under a `Camera2D`, put the mats in a **CanvasLayer** with `layer = -1`. The mat then stays fixed to the screen while cards move above it.

## Using it from code

```gdscript
@onready var player_mat: SuperPlaymat = $Playmats/PlayerMat

func _on_game_started(commander_identity: String) -> void:
	# Accepts "WU", "uw", "{W}{U}", "Azorius", "white blue", "" (colorless)…
	player_mat.set_identity(commander_identity, false)  # snap on load

func _on_commander_changed(identity: String) -> void:
	player_mat.identity = identity                       # animated radial wave

func _on_life_lost(_amount: int) -> void:
	player_mat.pulse(Color(1, 0.2, 0.15))                # red flash

func _on_turn_started() -> void:
	player_mat.pulse(Color(1, 1, 1), 0.4, 1.0)           # soft white glow
```

Scryfall's `color_identity` array (for example `["W","U"]`) can be passed as `"".join(card.color_identity)`.

**Signals:** `identity_changed(identity, display_name)` fires when a transition starts, and `transition_finished(identity)` fires when it ends.

**Helpers:** `ManaPalette.get_display_name("UBG")` returns `"Sultai"`. `ManaPalette.get_group("UBG")` returns `"Wedge"`. `ManaPalette.all_identities()` returns all 32 keys.

## Performance

* **About 3 fbm noise calls per pixel**, plus extra layers only for colors that are present. Layers whose amount is 0 are skipped with a uniform branch, so they cost almost nothing.
* `quality`: High = 5 noise octaves, Medium = 4, Low = 3. Use Low on laptops and integrated GPUs.
* `paused = true` freezes the animation while menus cover the board. The mat still draws, but nothing changes.
* For an extra-cheap option, put the mat in a `SubViewport` at half resolution and display it with a `TextureRect` (Stretch = Scale). That cuts fragment cost by about 4×.
* Time wraps every 10 hours, so long sessions never lose float precision.

## Customizing

* **Recolor everything:** edit `ManaPalette.swatch()` (the deep / base / light / accent colors for each mana color).
* **Change a color's personality:** edit `ManaPalette.traits()`. For example, give Blue a little `cell_amount` for an icy, cracked look.
* **Change the overall look:** adjust `pattern_scale`, `sigil_amount` and `brightness` in the Inspector, or the shader's `vignette_strength` and `grain_strength`.
