@tool
extends Node
class_name LanguageModelConnection


signal request_completed(response, request_id)
signal request_failed(error, request_id)

@export var provider : Provider:
	set(new_provider):
		provider = new_provider
		notify_property_list_changed()  # Trigger property list update when provider changes

# Custom property handling for model selection
var _model = ""
var _property_list = []

func _get(property):
	if property == "model":
		return _model

func _set(property, value):
	if property == "model":
		_model = value
		return true
	return false

func _get_property_list():
	_property_list = []
	
	if provider != null and provider.model_slugs.size() > 0:
		# Add model property with enum hint
		var models_hint_string = ",".join(provider.model_slugs)
		_property_list.append({
			"name": "model",
			"type": TYPE_STRING,
			"usage": PROPERTY_USAGE_DEFAULT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": models_hint_string
		})
	else:
		# Fallback to regular string if no provider or no models
		_property_list.append({
			"name": "model",
			"type": TYPE_STRING,
			"usage": PROPERTY_USAGE_DEFAULT
		})
	
	return _property_list

@export var target_resource: Resource  # Reference to instance of a resource

var active_requests = {}
var request_counter = 0

func _ready():
	add_to_group("language_model_connection")

func create_request() -> LanguageModelRequest:
	assert(provider != null, "Provider is required")
	assert(_model in provider.model_slugs, "Selected model is not supported by the provider")
	var req = LanguageModelRequest.new(self.provider)
	req.model = _model
	assert(req.model in provider.model_slugs)
	
	# Dynamically generate schema if target_resource is not null
	if target_resource != null:
		req.response_format = SchemaGenerator.schema(target_resource)
	
	return req

# Main method to send generation requests using the provider for formatting
func send_request(request : LanguageModelRequest):
	var request_id = request_counter
	request_counter += 1
	
	var http_request = HTTPRequest.new()
	http_request.timeout = 30.0
	add_child(http_request)
	
	# Connect signals and store request
	http_request.request_completed.connect(_on_request_completed.bind(request_id))
	active_requests[request_id] = http_request
	
	# Use provider to format request
	var body = provider.stringify_request_body(request)
	
	# Check if provider has custom headers method, otherwise use default
	var headers : PackedStringArray
	if provider.has_method("get_headers"):
		headers = provider.get_headers(provider.api_key)
	else:
		headers = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + provider.api_key
	])
	
	var url = provider.request_url(request)
	
	# Send the request
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		active_requests.erase(request_id)
		http_request.queue_free()
		emit_signal("request_failed", "Failed to make request: " + str(error), request_id)
		return -1
	
	return request_id

# Helper method to parse response into resource
func parse_response_with_schema(json_data):
	if target_resource != null:
		var resource_script = target_resource.get_script()
		# Use the from_json method of the resource class if available
		if resource_script.has_method("from_json"):
			return resource_script.from_json(json_data)
		# Otherwise use generic SchemaGenerator approach
		return SchemaGenerator.from_json(json_data, resource_script)
	return null

# Handle HTTP request completion
func _on_request_completed(result, response_code, headers, body, request_id):
	var http_request = active_requests[request_id]
	active_requests.erase(request_id)
	http_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("request_failed", "Request failed with code: " + str(result), request_id)
		return
		
	if response_code != 200:
		emit_signal("request_failed", "API returned error code: " + str(response_code) + " with body: " + body.get_string_from_utf8(), request_id)
		return
	print(body.get_string_from_utf8())
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		emit_signal("request_failed", "Failed to parse JSON response", request_id)
		return
	
	# Normalize response if provider has a normalize_response method
	if provider.has_method("normalize_response"):
		json = provider.normalize_response(json)
	
	if target_resource != null:
		# Extract content from the LLM response
		var resources = []
		for choice in json.choices:
			var content = choice.message.content
			# Convert the content to a resource using our schema
			var resource = parse_response_with_schema(content)
			if resource != null:
				resources.append(resource)
		
		# If only one choice was requested, return single resource for backward compatibility
		if resources.size() == 1:
			emit_signal("request_completed", resources[0], request_id)
		else:
			emit_signal("request_completed", resources, request_id)
	else:
		# Just return the raw JSON response
		emit_signal("request_completed", json, request_id)

# Cancel a specific request
func cancel_request(request_id: int) -> bool:
	if active_requests.has(request_id):
		var http_request = active_requests[request_id]
		http_request.cancel_request()
		active_requests.erase(request_id)
		http_request.queue_free()
		return true
	return false

# Cancel all active requests
func cancel_all_requests() -> void:
	for request_id in active_requests:
		var http_request = active_requests[request_id]
		http_request.cancel_request()
		http_request.queue_free()
	active_requests.clear()
