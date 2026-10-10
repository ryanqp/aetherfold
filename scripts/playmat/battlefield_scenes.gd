@tool
class_name BattlefieldScenes
extends RefCounted
## How each of the 32 playmat paintings comes to life (living_battlefield.gdshader).
## The painting for an identity is found by name in the art folder (same names as the felt mats:
## "White-Blue.jpg", "Colorless.jpg", …). Each preset lists only what differs from DEFAULTS.
## Drop in new paintings with the same names and they animate too; retune here if their content differs.

const DEFAULTS := {
	"water_amount": 0.6, "water_flow": Vector2(0.02, 0.01),
	"hot_amount": 0.4, "hot_color": Color(1.0, 0.45, 0.12), "heat_haze": 0.15,
	"foliage_amount": 0.5, "sky_amount": 0.0,
	"cloud_shadow": 0.45, "wind": Vector2(1.0, 0.25),
	"fog_amount": 0.15, "fog_color": Color(0.85, 0.88, 0.92),
	"rays_amount": 0.0, "ray_color": Color(1.0, 0.92, 0.7), "ray_angle": -0.6,
	"lightning": 0.0, "breath": 0.3,
	"p1_amount": 0.0, "p1_color": Color(1.0, 0.5, 0.15), "p1_speed": 0.08, "p1_size": 0.1, "p1_wobble": 0.3, "p1_hot_bias": 0.0,
	"p2_amount": 0.0, "p2_color": Color(1.0, 0.95, 0.7), "p2_speed": 0.015, "p2_size": 0.14, "p2_wobble": 0.6,
	"dissolve_color": Color(1.0, 0.8, 0.45),
}

## Particle looks, merged into a preset as p1_* or p2_*.
const EMBERS := {"color": Color(1.0, 0.48, 0.12), "speed": 0.1, "size": 0.09, "wobble": 0.35, "hot_bias": 0.6}
const ASH := {"color": Color(0.55, 0.53, 0.52), "speed": -0.025, "size": 0.08, "wobble": 0.9}
const SNOW := {"color": Color(0.95, 0.97, 1.0), "speed": -0.07, "size": 0.1, "wobble": 0.8}
const MOTES := {"color": Color(1.0, 0.9, 0.6), "speed": 0.012, "size": 0.12, "wobble": 0.7}
const FIREFLIES := {"color": Color(0.8, 1.0, 0.35), "speed": 0.008, "size": 0.13, "wobble": 1.0}
const SPORES := {"color": Color(0.75, 0.9, 0.6), "speed": 0.018, "size": 0.11, "wobble": 1.0}
const SPARKS := {"color": Color(0.55, 0.9, 1.0), "speed": 0.2, "size": 0.07, "wobble": 0.2}
const DUST := {"color": Color(0.85, 0.7, 0.5), "speed": 0.01, "size": 0.09, "wobble": 1.2}
const PETALS := {"color": Color(1.0, 0.92, 0.95), "speed": -0.03, "size": 0.1, "wobble": 1.2}

## identity → [scene note, effect overrides, particle 1 (look, amount), particle 2 (look, amount)]
const PRESETS := {
	"C": ["ash wastes and buried hedrons", {"water_amount": 0.0, "hot_amount": 0.0, "foliage_amount": 0.0, "cloud_shadow": 0.55, "fog_amount": 0.35, "fog_color": Color(0.8, 0.8, 0.82), "dissolve_color": Color(0.8, 0.9, 1.0)}, [ASH, 0.5], [MOTES, 0.2]],
	"W": ["sunlit plains and marble temple ruins", {"water_amount": 0.0, "foliage_amount": 0.9, "cloud_shadow": 0.6, "rays_amount": 0.8, "dissolve_color": Color(1.0, 0.92, 0.6)}, [MOTES, 0.45], null],
	"U": ["island coast and tide pools", {"water_amount": 1.1, "water_flow": Vector2(0.03, 0.02), "cloud_shadow": 0.45, "fog_amount": 0.25, "fog_color": Color(0.9, 0.95, 1.0), "dissolve_color": Color(0.5, 0.85, 1.0)}, null, null],
	"B": ["cypress swamp and mudflat", {"water_amount": 0.8, "water_flow": Vector2(0.005, 0.0), "cloud_shadow": 0.0, "fog_amount": 0.5, "fog_color": Color(0.32, 0.3, 0.38), "dissolve_color": Color(0.7, 0.45, 1.0)}, [FIREFLIES, 0.55], null],
	"R": ["lava canyon and basalt shelf", {"hot_amount": 1.2, "heat_haze": 0.9, "foliage_amount": 0.0, "cloud_shadow": 0.3, "fog_amount": 0.15, "fog_color": Color(0.35, 0.18, 0.12), "dissolve_color": Color(1.0, 0.5, 0.15)}, [EMBERS, 0.85], [ASH, 0.25]],
	"G": ["forest clearing and roots", {"foliage_amount": 1.2, "cloud_shadow": 0.35, "rays_amount": 0.55, "ray_color": Color(0.95, 1.0, 0.7), "dissolve_color": Color(0.7, 1.0, 0.4)}, [FIREFLIES, 0.35], [MOTES, 0.25]],
	"WU": ["marble plaza and canal", {"water_amount": 1.0, "water_flow": Vector2(0.0, 0.03), "cloud_shadow": 0.55, "rays_amount": 0.4}, [MOTES, 0.3], null],
	"WB": ["basilica crypt court", {"water_amount": 0.0, "hot_amount": 1.0, "heat_haze": 0.1, "cloud_shadow": 0.3, "fog_amount": 0.3, "fog_color": Color(0.6, 0.6, 0.62), "rays_amount": 0.3, "ray_color": Color(0.9, 0.92, 1.0)}, [MOTES, 0.35], null],
	"WR": ["fortress parade yard", {"water_amount": 0.0, "hot_amount": 0.8, "heat_haze": 0.2, "cloud_shadow": 0.6}, [DUST, 0.4], null],
	"WG": ["temple grove", {"water_amount": 0.3, "foliage_amount": 1.1, "cloud_shadow": 0.4, "rays_amount": 0.55}, [PETALS, 0.4], [MOTES, 0.25]],
	"UB": ["undercity canal quay", {"water_amount": 0.3, "water_flow": Vector2(0.02, 0.0), "hot_amount": 1.0, "cloud_shadow": 0.0, "fog_amount": 0.45, "fog_color": Color(0.2, 0.26, 0.38), "dissolve_color": Color(0.5, 0.6, 1.0)}, null, null],
	"UR": ["steam workshop yard", {"water_amount": 0.8, "water_flow": Vector2(0.0, 0.04), "hot_amount": 1.0, "heat_haze": 0.5, "cloud_shadow": 0.2, "fog_amount": 0.4, "fog_color": Color(0.9, 0.92, 0.95), "lightning": 0.15}, [SPARKS, 0.45], [EMBERS, 0.25]],
	"UG": ["tidal mangrove wetland", {"water_amount": 1.0, "water_flow": Vector2(0.015, 0.01), "foliage_amount": 1.0, "fog_amount": 0.25, "fog_color": Color(0.8, 0.92, 0.88)}, [FIREFLIES, 0.3], null],
	"BR": ["volcanic pit", {"hot_amount": 1.3, "heat_haze": 0.9, "foliage_amount": 0.0, "cloud_shadow": 0.0, "fog_amount": 0.3, "fog_color": Color(0.25, 0.1, 0.08), "dissolve_color": Color(1.0, 0.35, 0.1)}, [EMBERS, 1.0], [ASH, 0.3]],
	"BG": ["fungal rot garden", {"foliage_amount": 0.8, "cloud_shadow": 0.0, "fog_amount": 0.45, "fog_color": Color(0.35, 0.42, 0.3)}, [SPORES, 0.6], [FIREFLIES, 0.2]],
	"RG": ["smashed canyon wilds", {"water_amount": 0.0, "hot_amount": 0.3, "foliage_amount": 1.0, "cloud_shadow": 0.6, "rays_amount": 0.3}, [DUST, 0.35], null],
	"WUB": ["filigree reflecting court", {"water_amount": 1.0, "water_flow": Vector2(0.0, 0.0), "cloud_shadow": 0.45, "rays_amount": 0.35, "ray_color": Color(0.85, 0.92, 1.0)}, [MOTES, 0.35], null],
	"WUR": ["snow monastery court", {"water_amount": 0.8, "hot_amount": 0.9, "cloud_shadow": 0.4, "fog_amount": 0.25, "fog_color": Color(0.95, 0.97, 1.0)}, [SNOW, 0.75], null],
	"WUG": ["coastal castle lawn", {"water_amount": 1.0, "water_flow": Vector2(0.02, 0.0), "foliage_amount": 0.9, "sky_amount": 0.8, "cloud_shadow": 0.55, "rays_amount": 0.45}, [PETALS, 0.35], null],
	"WBR": ["steppe war camp", {"water_amount": 0.0, "hot_amount": 0.8, "foliage_amount": 0.8, "cloud_shadow": 0.7, "wind": Vector2(1.0, 0.1)}, [DUST, 0.45], [EMBERS, 0.15]],
	"WBG": ["fortified kin-tree grove", {"foliage_amount": 0.9, "cloud_shadow": 0.4, "fog_amount": 0.2, "rays_amount": 0.4}, [MOTES, 0.4], null],
	"WRG": ["jungle canyon altar", {"water_amount": 0.4, "foliage_amount": 1.2, "cloud_shadow": 0.5, "rays_amount": 0.45}, [FIREFLIES, 0.3], [MOTES, 0.2]],
	"UBR": ["ash beach and lava coast", {"water_amount": 1.2, "water_flow": Vector2(-0.04, 0.0), "hot_amount": 1.2, "heat_haze": 0.6, "cloud_shadow": 0.3, "fog_amount": 0.25, "fog_color": Color(0.22, 0.2, 0.22), "lightning": 0.3}, [EMBERS, 0.55], [ASH, 0.35]],
	"UBG": ["jungle river terrace", {"water_amount": 0.9, "water_flow": Vector2(0.03, 0.0), "foliage_amount": 1.0, "fog_amount": 0.35, "fog_color": Color(0.6, 0.72, 0.62)}, [FIREFLIES, 0.35], null],
	"URG": ["frontier stream clearing", {"water_amount": 1.1, "water_flow": Vector2(0.02, 0.06), "foliage_amount": 1.0, "cloud_shadow": 0.5}, [SNOW, 0.15], null],
	"BRG": ["volcanic jungle basin", {"hot_amount": 1.0, "heat_haze": 0.6, "foliage_amount": 0.9, "fog_amount": 0.3, "fog_color": Color(0.3, 0.18, 0.12)}, [EMBERS, 0.7], [SPORES, 0.2]],
	"WUBR": ["citadel between storm sea and volcano", {"water_amount": 1.2, "water_flow": Vector2(0.04, 0.0), "hot_amount": 1.1, "heat_haze": 0.4, "cloud_shadow": 0.6, "lightning": 0.75, "fog_amount": 0.2, "fog_color": Color(0.4, 0.42, 0.5)}, [EMBERS, 0.5], null],
	"WUBG": ["misty lakeside cloister", {"water_amount": 0.9, "foliage_amount": 0.8, "cloud_shadow": 0.3, "fog_amount": 0.55, "fog_color": Color(0.88, 0.9, 0.92)}, [MOTES, 0.3], null],
	"WURG": ["highland lake terrace", {"water_amount": 1.0, "foliage_amount": 0.7, "sky_amount": 1.0, "cloud_shadow": 0.65, "rays_amount": 0.35}, [MOTES, 0.25], null],
	"WBRG": ["dry clan valley", {"water_amount": 0.0, "hot_amount": 0.4, "heat_haze": 0.35, "foliage_amount": 0.7, "cloud_shadow": 0.7}, [DUST, 0.45], null],
	"UBRG": ["wild river gorge", {"water_amount": 1.2, "water_flow": Vector2(0.0, 0.07), "foliage_amount": 1.0, "sky_amount": 0.6, "cloud_shadow": 0.45, "fog_amount": 0.35, "fog_color": Color(0.75, 0.8, 0.85)}, [SPORES, 0.2], null],
	"WUBRG": ["confluence amphitheater", {"water_amount": 1.0, "water_flow": Vector2(0.03, 0.02), "hot_amount": 0.6, "foliage_amount": 0.9, "cloud_shadow": 0.5, "rays_amount": 0.4, "dissolve_color": Color(0.9, 0.7, 1.0)}, [MOTES, 0.45], [FIREFLIES, 0.2]],
}


## The painting's file name for an identity (WUBRG order): "White-Blue.jpg", "Colorless.jpg", …
static func file_for(identity: String) -> String:
	var key := ManaPalette.normalize(identity)
	if key == "C":
		return "Colorless.jpg"
	var names := {"W": "White", "U": "Blue", "B": "Black", "R": "Red", "G": "Green"}
	var parts := PackedStringArray()
	for ch in key:
		parts.append(names[ch])
	return "%s.jpg" % "-".join(parts)


static func scene_note(identity: String) -> String:
	var p = PRESETS.get(ManaPalette.normalize(identity))
	return "" if p == null else str(p[0])


## All shader effect values for an identity.
static func build(identity: String) -> Dictionary:
	var out := DEFAULTS.duplicate()
	var p = PRESETS.get(ManaPalette.normalize(identity))
	if p == null:
		return out
	for k in p[1]:
		out[k] = p[1][k]
	_particles(out, "p1_", p[2])
	_particles(out, "p2_", p[3])
	return out


static func _particles(out: Dictionary, prefix: String, spec) -> void:
	if spec == null:
		out[prefix + "amount"] = 0.0
		return
	var look: Dictionary = spec[0]
	out[prefix + "amount"] = float(spec[1])
	for k in look:
		if DEFAULTS.has(prefix + k): # e.g. hot_bias only exists for particle system 1
			out[prefix + k] = look[k]
