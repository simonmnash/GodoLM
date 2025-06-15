@tool
extends Resource
class_name Provider

var host_base_url : String
var model_slugs : Array[String]
var api_key : String

func _ready() -> void:
	assert(len(host_base_url)>0)
	assert(len(model_slugs)>0)

func default_model() -> String:
	return model_slugs[0]

func request_url(request : LanguageModelRequest) -> String:
	var url = host_base_url + "/chat/completions"
	return url

func stringify_request_body(request : LanguageModelRequest) -> String:
	var body = {
		"model": request.model,
		"messages": request.context,
		"tools": request.tools,
		"tool_choice": request.tool_choice,
		"temperature": request.temperature,
		"max_tokens": request.max_tokens
	}
	
	if request.response_format != null:
		body["response_format"] = {
			"type": "json_schema",
			"json_schema": {
				"schema": request.response_format,
				"name": "response",
				"strict": true
			}
		}
	return JSON.stringify(body)

# Extract JSON from text response (to be extended by specific providers)
static func extract_json(text: String):
	# Try normal parsing first
	var json_result = JSON.parse_string(text)
	if json_result != null:
		return json_result
	
	return null
