class_name OracleStructure
extends RefCounted

## Splits Oracle text into ability clauses. This classifies structure.
## It does not choose modes, targets, or types, and it does not apply effects.
## Executable cards still need IR. A `{cost}:` line is an activated ability (CR 602.1).

static func clauses(oracle_text: String) -> Array:
	var out: Array = []
	var cost_re := RegEx.new()
	cost_re.compile("^(\\{[^}]+\\})+")
	for raw in oracle_text.replace("\r", "").split("\n"):
		var line := str(raw).strip_edges()
		if line == "" or line.begins_with("("):
			continue
		var found := cost_re.search(line)
		if found != null and line.substr(found.get_end()).strip_edges().begins_with(":"):
			out.append({
				kind = "ACTIVATED",
				cost = found.get_string(),
				text = line,
			})
		elif line.begins_with("Whenever ") or line.begins_with("When ") or line.begins_with("At "):
			out.append({kind = "TRIGGERED", text = line})
		else:
			out.append({kind = "STATIC", text = line})
	return out
