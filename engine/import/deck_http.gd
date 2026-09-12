class_name DeckHttp
extends RefCounted

const UA := "Aetherfold/1.0 (Commander table; deck import)"
const ACCEPT := "application/json, text/plain;q=0.9, */*;q=0.8"


static func headers() -> PackedStringArray:
	return PackedStringArray([
		"User-Agent: %s" % UA,
		"Accept: %s" % ACCEPT,
	])


static func get_sync(url: String, timeout_ms: int = 20000) -> Dictionary:
	var parsed := _split_url(url)
	if parsed.is_empty():
		return {ok = false, status = 0, text = "", error = "Invalid URL."}
	var http := HTTPClient.new()
	var tls := TLSOptions.client()
	var err := http.connect_to_host(str(parsed.host), int(parsed.port), tls)
	if err != OK:
		return {ok = false, status = 0, text = "", error = "Could not connect."}
	var start := Time.get_ticks_msec()
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if Time.get_ticks_msec() - start > timeout_ms:
			return {ok = false, status = 0, text = "", error = "Connection timed out."}
		OS.delay_msec(15)
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {ok = false, status = 0, text = "", error = "Could not connect to host."}
	err = http.request(HTTPClient.METHOD_GET, str(parsed.path), headers())
	if err != OK:
		return {ok = false, status = 0, text = "", error = "Request failed."}
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() - start > timeout_ms:
			return {ok = false, status = 0, text = "", error = "Request timed out."}
		OS.delay_msec(15)
	var code := http.get_response_code()
	var body := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			body.append_array(chunk)
		if Time.get_ticks_msec() - start > timeout_ms:
			return {ok = false, status = code, text = "", error = "Timed out reading body."}
		OS.delay_msec(10)
	var text := body.get_string_from_utf8()
	if code == 401 or code == 403:
		return {ok = false, status = code, text = text, error = "Deck may be private, deleted, or temporarily unavailable."}
	if code == 404:
		return {ok = false, status = code, text = text, error = "Deck not found."}
	if code != 200:
		return {ok = false, status = code, text = text, error = "HTTP %d." % code}
	return {ok = true, status = code, text = text, error = ""}


static func post_sync(url: String, json_body: String, timeout_ms: int = 20000) -> Dictionary:
	var parsed := _split_url(url)
	if parsed.is_empty():
		return {ok = false, status = 0, text = "", error = "Invalid URL."}
	var http := HTTPClient.new()
	var err := http.connect_to_host(str(parsed.host), int(parsed.port), TLSOptions.client())
	if err != OK:
		return {ok = false, status = 0, text = "", error = "Could not connect."}
	var start := Time.get_ticks_msec()
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if Time.get_ticks_msec() - start > timeout_ms:
			return {ok = false, status = 0, text = "", error = "Connection timed out."}
		OS.delay_msec(15)
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {ok = false, status = 0, text = "", error = "Could not connect to host."}
	var hdrs := headers()
	hdrs.append("Content-Type: application/json")
	err = http.request(HTTPClient.METHOD_POST, str(parsed.path), hdrs, json_body)
	if err != OK:
		return {ok = false, status = 0, text = "", error = "Request failed."}
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() - start > timeout_ms:
			return {ok = false, status = 0, text = "", error = "Request timed out."}
		OS.delay_msec(15)
	var code := http.get_response_code()
	var body := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			body.append_array(chunk)
		if Time.get_ticks_msec() - start > timeout_ms:
			break
		OS.delay_msec(10)
	var text := body.get_string_from_utf8()
	if code != 200:
		return {ok = false, status = code, text = text, error = "HTTP %d." % code}
	return {ok = true, status = code, text = text, error = ""}


static func _split_url(url: String) -> Dictionary:
	var u := url.strip_edges()
	if u.begins_with("http://"):
		return {}
	if not u.begins_with("https://"):
		return {}
	u = u.substr(8)
	var slash := u.find("/")
	var host := u if slash < 0 else u.substr(0, slash)
	var path := "/" if slash < 0 else u.substr(slash)
	if host == "" or host.find(" ") >= 0:
		return {}
	return {host = host, port = 443, path = path}
