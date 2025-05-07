@tool
extends Node
class_name LanguageModelConnection


signal request_completed(response, request_id)
signal request_failed(error, request_id)

@export var provider : Provider
@export var model : String
@export var target_resource: Resource  # Reference to instance of a resource

var active_requests = {}
var request_counter = 0

func _ready():
	add_to_group("language_model_connection")
	

func create_request() -> LanguageModelRequest:
	assert(self.model in provider.model_slugs)
	var req = LanguageModelRequest.new(self.provider)
	req.model = self.model
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
	var headers = PackedStringArray([
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
	
	if target_resource != null:
		# Extract content from the LLM response
		var content = json.choices[0].message.content
		# Convert the content to a resource using our schema
		var resource = parse_response_with_schema(content)
		emit_signal("request_completed", resource, request_id)
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
