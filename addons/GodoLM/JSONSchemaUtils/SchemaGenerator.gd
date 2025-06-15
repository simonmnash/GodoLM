extends Object
class_name SchemaGenerator

const _TYPE_MAP := {
	TYPE_BOOL:    "boolean",
	TYPE_STRING:  "string",
	TYPE_INT:     "integer",
	TYPE_FLOAT:   "number",
	TYPE_COLOR:   "string",
	TYPE_ARRAY:   "array"
}

static func _is_editor_prop(prop: Dictionary, res: Resource) -> bool:
	# Check if the resource has PROPERTY_DESCRIPTIONS constant
	if res.has_method("get_script") and res.get_script() != null:
		# Try to access PROPERTY_DESCRIPTIONS through the resource itself
		if "PROPERTY_DESCRIPTIONS" in res:
			var property_descriptions = res.PROPERTY_DESCRIPTIONS
			return prop.name in property_descriptions
	
	# Fallback to the old behavior
	# Enumerate @export vars while skipping built-in properties and private properties
	if prop.name in ["resource_local_to_scene", "resource_path", "resource_name", "script"] or prop.name.begins_with("_") or prop.name.begins_with("metadata/"):
		return false
	
	# Only include properties that are exposed to the editor
	return (prop.usage & PROPERTY_USAGE_EDITOR) != 0
	
static func _to_hex(c: Color) -> String:
	return "#" + c.to_html(false)

static func json_dict(res: Resource, max_recursion: int = 4) -> Dictionary:
	if max_recursion <= 0:
		return {}
		
	var result := {}
	
	for p in res.get_property_list():
		if not _is_editor_prop(p, res):
			continue
			
		var val = res.get(p.name)
		
		# Handle special types
		if p.type == TYPE_COLOR:
			val = _to_hex(val)
		# Handle Resource objects recursively
		elif val is Resource:
			val = json_dict(val, max_recursion - 1)
		# Handle arrays that might contain resources
		elif val is Array:
			var new_array = []
			for item in val:
				if item is Resource:
					new_array.append(json_dict(item, max_recursion - 1))
				else:
					new_array.append(item)
			val = new_array
			
		result[p.name] = val
	
	return result

static func schema(res: Resource, max_recursion: int = 4) -> Dictionary:
	var schema := {
		"type": "object",
		"properties": {},
		"required": [],
		"additionalProperties": false
	}
	
	for p in res.get_property_list():
		if not _is_editor_prop(p, res):
			continue
		
		if not (res.get_script().has_source_code() and "PROPERTY_DESCRIPTIONS" in res and res.PROPERTY_DESCRIPTIONS.has(p.name)):
			continue
		
		# Get JSON type for this property
		var json_type = _TYPE_MAP.get(p.type, "string")
		var prop_schema := {"type": json_type}
		prop_schema["description"] = res.PROPERTY_DESCRIPTIONS[p.name]
		
		# Handle arrays by defining the items property. We will only ever deal with typed arrays.
		if json_type == "array":
			# Get the class type from hint_string if available
			var array_class = p.hint_string.split(":", true, 1)[1].strip_edges()
			
			# Check if we've reached the recursion limit
			if max_recursion <= 0:
				# At max recursion, all arrays should be empty
				prop_schema["items"] = {
					"type": "object",
					"properties": {},
					"required": [],
					"additionalProperties": false
				}
				# Add default empty array
				# prop_schema["default"] = []
			else:
				# Try to find the class using ProjectSettings
				var script_path = ""
				var global_classes = ProjectSettings.get_global_class_list()
				
				if global_classes:
					for script_class in global_classes:
						if script_class["class"] == array_class:
							script_path = script_class["path"]
							break
				
				if script_path:
					# Found the script path, load it and instantiate
					var script = load(script_path)
					if script:
						var instance = script.new()
						# Recursive call with decremented max_recursion
						prop_schema["items"] = schema(instance, max_recursion - 1)
		# Handle individual Resource properties
		elif p.type == TYPE_OBJECT and p.hint_string != "":
			var resource_class = p.hint_string.strip_edges()
			
			# Check if we've reached the recursion limit
			if max_recursion <= 0:
				# At max recursion, return empty object schema
				prop_schema = {
					"type": "object",
					"properties": {},
					"required": [],
					"additionalProperties": false
				}
			else:
				# Try to find the class using ProjectSettings
				var script_path = ""
				var global_classes = ProjectSettings.get_global_class_list()
				
				if global_classes:
					for script_class in global_classes:
						if script_class["class"] == resource_class:
							script_path = script_class["path"]
							break
				
				if script_path:
					# Found the script path, load it and instantiate
					var script = load(script_path)
					if script:
						var instance = script.new()
						# Recursive call with decremented max_recursion
						prop_schema = schema(instance, max_recursion - 1)
				else:
					# Fallback to basic object if class not found
					prop_schema["type"] = "object"
			
			# Add the description
			prop_schema["description"] = res.PROPERTY_DESCRIPTIONS[p.name]
		
		schema.properties[p.name] = prop_schema
		schema.required.append(p.name)
	
	# Add reflection rubric if present
	if res.has_method("get_script") and res.get_script() != null:
		if "REFLECTION_RUBRIC" in res:
			var rubric = res.REFLECTION_RUBRIC
			for criterion_key in rubric:
				var criterion_schema = {
					"type": "boolean",
					"description": rubric[criterion_key]
				}
				schema.properties[criterion_key] = criterion_schema
				schema.required.append(criterion_key)
	
	return schema

# Helper function to remove JavaScript-style comments from JSON
static func _remove_comments_from_json(json_str: String) -> String:
	var lines = json_str.split("\n")
	var result = []
	
	for line in lines:
		var comment_pos = line.find("//")
		if comment_pos != -1:
			# Only keep the part before the comment
			result.append(line.substr(0, comment_pos))
		else:
			result.append(line)
	
	return "\n".join(result)

# Extract the first complete JSON object from a string
static func _extract_first_json_object(text: String) -> Dictionary:
	# First try direct parsing - maybe it's already valid JSON
	var direct_parse = JSON.parse_string(text)
	if direct_parse != null and typeof(direct_parse) == TYPE_DICTIONARY:
		return direct_parse
		
	# If the text starts with { and contains a }, try to extract just the first JSON object
	if text.begins_with("{") and "}" in text:
		var nesting_level = 0
		var in_string = false
		var escape_next = false
		var end_pos = -1
		
		for i in range(text.length()):
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
					if nesting_level == 0:
						end_pos = i
						break
			
		if end_pos > 0:
			var json_text = text.substr(0, end_pos + 1)
			var result = JSON.parse_string(json_text)
			if result != null and typeof(result) == TYPE_DICTIONARY:
				return result
	
	# If we got here, we couldn't extract a valid JSON object
	return {}

# Parse JSON data with comment removal
static func parse_json(json_data) -> Dictionary:
	var parsed_json_data = json_data
	
	# Handle different input types
	if typeof(json_data) == TYPE_STRING:
		# First try to extract the first complete JSON object from the string
		var first_json = _extract_first_json_object(json_data)
		if not first_json.is_empty():
			return first_json
			
		# If that fails, try normal extraction
		var extracted = Provider.extract_json(json_data)
		if extracted != null:
			return extracted
			
		# If that fails, try the regular parsing approach
		print("RESPONSE")
		print(json_data)
		var cleaned_json = _remove_comments_from_json(json_data)
		print(cleaned_json)
		# Try to parse as JSON string
		var parse_result = JSON.parse_string(cleaned_json)
		if parse_result != null:
			parsed_json_data = parse_result
		else:
			push_error("Failed to parse JSON string")
			return {}
	
	# If we have an API response, extract the content
	if typeof(parsed_json_data) == TYPE_DICTIONARY and parsed_json_data.has("choices"):
		# Extract content from API response
		if parsed_json_data.has("choices") and parsed_json_data.choices.size() > 0:
			var content = parsed_json_data.choices[0].message.content
			
			# First try to extract the first JSON object from the content
			var first_json = _extract_first_json_object(content)
			if not first_json.is_empty():
				return first_json
				
			# If that fails, try regular extraction
			var extracted = Provider.extract_json(content)
			if extracted != null:
				return extracted
				
			# Remove comments before parsing
			content = _remove_comments_from_json(content)
			
			# Try to parse the content string
			var content_parse = JSON.parse_string(content)
			if content_parse != null:
				parsed_json_data = content_parse
			else:
				push_error("Failed to parse content JSON")
				return {}
	
	return parsed_json_data

# Generic from_json for resources
static func from_json(json_data, resource_type, default_values := {}) -> Resource:
	var res = resource_type.new()
	var parsed_data = parse_json(json_data)
	
	if parsed_data.is_empty():
		return res
	
	# Extract rubric results if present
	var rubric_results = {}
	if resource_type.has_method("new") and "REFLECTION_RUBRIC" in resource_type:
		for criterion_key in resource_type.REFLECTION_RUBRIC:
			if parsed_data.has(criterion_key):
				rubric_results[criterion_key] = parsed_data.get(criterion_key)
	
	# Apply properties based on the parsed data
	for prop in res.get_property_list():
		if not _is_editor_prop(prop, res):
			continue
		if parsed_data.has(prop.name):
			var value = parsed_data.get(prop.name)
			# Handle arrays specially
			if prop.type == TYPE_ARRAY and ":" in prop.hint_string:
				var array_class = prop.hint_string.split(":", true, 1)[1].strip_edges()
				
				# Try to find the class script
				var script_path = ""
				var global_classes = ProjectSettings.get_global_class_list()
				
				if global_classes:
					for script_class in global_classes:
						if script_class["class"] == array_class:
							script_path = script_class["path"]
							break
				
				if script_path and value is Array:
					var script = load(script_path)
					if script:
						# Instead of creating a new array, modify the existing one
						# First, clear the existing array
						var existing_array = res.get(prop.name)
						
						# If array is null or not an array, initialize it
						if not existing_array is Array:
							print("Property doesn't contain an array, creating one")
							existing_array = []
							res.set(prop.name, existing_array)
						
						# Convert and add each item to the existing array
						for item in value:
							# Recursively convert each item
							var resource_item = from_json(item, script)
							
							# Try different approaches to add the item
							# 1. Try to modify the existing array directly
							var array_to_modify = res.get(prop.name)
							if array_to_modify is Array:
								array_to_modify.append(resource_item)
								
								# Check if the item was added
							else:
								print("WARNING: Could not access array properly, trying direct set")
								# 2. Try direct set as fallback
								res.set(prop.name, [resource_item])
			# Handle individual Resource properties
			elif prop.type == TYPE_OBJECT and prop.hint_string != "" and value is Dictionary:
				var resource_class = prop.hint_string.strip_edges()
				
				# Try to find the class script
				var script_path = ""
				var global_classes = ProjectSettings.get_global_class_list()
				
				if global_classes:
					for script_class in global_classes:
						if script_class["class"] == resource_class:
							script_path = script_class["path"]
							break
				
				if script_path:
					var script = load(script_path)
					if script:
						# Recursively convert the dictionary to a Resource
						var resource_item = from_json(value, script)
						res.set(prop.name, resource_item)
			else:
				# Non-array, non-Resource property, set directly
				res.set(prop.name, value)
		elif default_values.has(prop.name):
			res.set(prop.name, default_values.get(prop.name))
	
	# Final verification
	for prop in res.get_property_list():
		if _is_editor_prop(prop, res) and prop.type == TYPE_ARRAY:
			var arr = res.get(prop.name)
	
	# Store rubric results as metadata if any were found
	if not rubric_results.is_empty():
		res.set_meta("_rubric_results", rubric_results)
	
	return res 
