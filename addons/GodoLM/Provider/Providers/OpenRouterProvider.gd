@tool
extends Provider
class_name OpenRouterProvider

func _init():
	host_base_url = "https://openrouter.ai/api/v1"
	model_slugs = ["mistralai/ministral-3b",
				   "mistralai/ministral-8b",
				   "mistralai/mistral-small-3.1-24b-instruct",
				   "mistralai/mistral-medium-3"]

# Override to handle OpenRouter specific JSON extraction
static func extract_json(text: String):
	# Try normal parsing first
	var json_result = JSON.parse_string(text)
	if json_result != null:
		return json_result
	
	# If parsing failed, try to find valid JSON objects
	var valid_objects = find_valid_json_objects(text)
	if valid_objects.size() > 0:
		# Return the last valid object found (often the most complete one)
		return valid_objects[-1].parsed
	
	return null

# Utility function to find valid JSON objects in a potentially malformed string
static func find_valid_json_objects(text: String) -> Array:
	var valid_objects = []
	var i = 0
	
	while i < len(text):
		# Look for opening brace of an object
		if text[i] == '{':
			var start_pos = i
			var nesting_level = 1
			var in_string = false
			var escape_next = false
			i += 1  # Move past the opening brace
			
			# Track nesting to find matching closing brace
			while i < len(text) and nesting_level > 0:
				var char = text[i]
				
				if escape_next:
					escape_next = false
				elif char == '\\':
					escape_next = true
				elif char == '"' and not escape_next:
					in_string = not in_string
				elif not in_string:
					if char == '{':
						nesting_level += 1
					elif char == '}':
						nesting_level -= 1
						
				i += 1
			
			# If we found a matching closing brace
			if nesting_level == 0:
				var potential_json = text.substr(start_pos, i - start_pos)
				var parse_result = JSON.parse_string(potential_json)
				
				if parse_result != null:
					valid_objects.append({
						"text": potential_json,
						"parsed": parse_result,
						"start": start_pos,
						"end": i - 1
					})
			else:
				# Unbalanced braces, move on
				i = start_pos + 1
		else:
			i += 1
	
	return valid_objects 
