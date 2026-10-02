@tool
extends McpTestSuite

## Typing the host's online address: "ip", "ip:port" and host names (scripts/net/game_net.gd).

const GameNetScript := preload("res://scripts/net/game_net.gd")


func suite_name() -> String:
	return "net_address"


func test_plain_ip_uses_the_default_port() -> void:
	var a: Dictionary = GameNetScript.parse_address("203.0.113.5")
	assert_eq(str(a.host), "203.0.113.5")
	assert_eq(int(a.port), GameNetScript.GAME_PORT)


func test_ip_with_a_port() -> void:
	var a: Dictionary = GameNetScript.parse_address("  203.0.113.5:30000 ")
	assert_eq(str(a.host), "203.0.113.5")
	assert_eq(int(a.port), 30000)


func test_host_name() -> void:
	var a: Dictionary = GameNetScript.parse_address("lunar.example.com")
	assert_eq(str(a.host), "lunar.example.com")
	assert_eq(int(a.port), GameNetScript.GAME_PORT)


func test_bad_port_falls_back_to_default() -> void:
	var a: Dictionary = GameNetScript.parse_address("203.0.113.5:99999")
	assert_eq(str(a.host), "203.0.113.5")
	assert_eq(int(a.port), GameNetScript.GAME_PORT)
