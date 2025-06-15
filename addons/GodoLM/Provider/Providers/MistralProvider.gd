@tool
extends Provider
class_name MistralProvider

func _init():
	host_base_url = "https://api.mistral.ai/v1"
	# Latest Mistral models as of the documentation
	model_slugs = [
		"ministral-3b-latest",          # Latest 8B model
		"ministral-8b-latest",          # Latest 8B model
		"mistral-small-latest",         # Small model
		"mistral-medium-latest",        # Medium model
		"mistral-large-latest",         # Large model
	]

# Override to handle Mistral specific JSON extraction
static func extract_json(text: String):
	# Try normal parsing first
	var json_result = JSON.parse_string(text)
	if json_result != null:
		return json_result
	return null

# Mistral uses the same request format as OpenAI for structured output
# No need to override stringify_request_body - the base implementation works perfectly
# Mistral supports response_format with json_schema just like OpenAI
func stringify_request_body(request : LanguageModelRequest) -> String:
	var body = {
		"model": request.model,
		"messages": request.context,
		"temperature": request.temperature,
		"max_tokens": request.max_tokens,
		"n": request.n
	}
	
	# Add tools if present
	if request.tools.size() > 0:
		body["tools"] = request.tools
		body["tool_choice"] = request.tool_choice
	
	# Mistral supports response_format with json_schema similar to OpenAI
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
