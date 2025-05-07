@tool
extends EditorPlugin

func _enter_tree():
	# Register Provider as a custom resource type
	add_custom_type("Provider", "Resource", preload("res://addons/GodoLM/Provider/provider.gd"), preload("res://addons/GodoLM/godolm.png"))
	
	# Register specific Provider implementations
	add_custom_type("OpenRouterProvider", "Resource", preload("res://addons/GodoLM/Provider/Providers/OpenRouterProvider.gd"), preload("res://addons/GodoLM/godolm.png"))
	
	# Register the LanguageModelRequest class if needed
	if ResourceLoader.exists("res://addons/GodoLM/LanguageModelRequest/LanguageModelRequest.gd"):
		var request_script = load("res://addons/GodoLM/LanguageModelRequest/LanguageModelRequest.gd")
		add_custom_type("LanguageModelRequest", "Resource", request_script, preload("res://addons/GodoLM/godolm.png"))

func _exit_tree():
	# Clean up custom types when plugin is deactivated
	remove_custom_type("Provider")
	remove_custom_type("OpenRouterProvider")
	remove_custom_type("LanguageModelRequest") 
