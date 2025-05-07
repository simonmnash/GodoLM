extends Object
class_name LanguageModelRequest

var remote_models = ["mistralai/mistral-small-3.1-24b-instruct", "mistralai/ministral-3b"]

var context: Array[Dictionary] :
	set(v) :
		for msg in v:
			assert(msg.get('role') in ['system', 'user', 'assistant'])
		context = v

var provider : Provider
var model: String
var temperature: float = 0.7
var max_tokens: int = 1024
var response_format = null
var tools: Array = []
var tool_choice: String = "none"

func _init(provider: Provider) -> void:
	for msg in context:
		assert(msg.get('role') in ['system', 'user', 'assistant'])
	assert(temperature <= 1.0)
	assert(temperature >= 0.0)
	assert(max_tokens < 2048)
	assert(tool_choice in ['none', 'auto'])

func add_context(content : String, role : String = "system") -> Array[Dictionary]:
	assert(role in ['system', 'user', 'assistant', 'tool'])
	context.append({'role': role, 'content': content})
	return context
