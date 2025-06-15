# GodoLM

A high-level interface for invoking language models in Godot games, using JSONSchema based constraints to parse responses into arbitrary resources.

This is a lightly maintained side project that I periodically update based on the development needs of a game I am working on. It is primarily designed for easy experimentation.

## Installation

1. Download the GodoLM addon from the Godot Asset Library or from GitHub
2. Place the `addons/GodoLM` folder in your project's `addons` directory
3. Enable the plugin in Project Settings → Plugins

## Usage

### Basic Setup

1. Add a `LanguageModelConnection` node to your scene
2. Configure a provider (e.g., MistralProvider) with your API key.
4. Create requests - add context and a target resource type.
5. Send the request and get a new resource back.

## Code Example

GodoLM supports structured responses using JSON Schema:

Define a resource:

```gdscript
# Define a resource for structured data
class_name Sword
extends Resource

const PROPERTY_DESCRIPTIONS = {
    "sword_name": "The name of the sword",
    "blade_material": "Material the blade is made from (e.g. steel, iron, silver, ice)",
    "hilt_material": "Material the handle is made from (e.g. leather, wood, bone, carbon fibre)",
    "description": "A detailed description of the sword's appearance and history",
    "damage": "The base damage points this sword deals per hit",
    "speed": "Attack speed modifier (higher is faster)",
    "length": "The length of the sword in centimeters",
    "blade_color": "Color of the blade in hex format (e.g. #0080FF)",
    "accent_color": "Color of any decorative accents or trim in hex format (e.g. #FFD700)",
    "hilt_color": "Color of the sword's hilt in hex format (e.g. #8B4513)"
}

@export var sword_name: String
@export var blade_material: String
@export var hilt_material: String
@export var description: String
@export var damage: int
@export var speed: float
@export var length: float
@export var blade_color: Color
@export var accent_color: Color
@export var hilt_color: Color
```
Then use the LanguageModelRequest Node to create requests and parse responses:
```gdscript
# Send a request.
func send_sword_request():
    var request = $LanguageModelConnection.create_request()
    request.add_context("Something found at the bottom of a lake.")
    $LanguageModelConnection.send_request(request)

# Handle the completed request when $LanguageModelConnection completes the request.
func _on_request_completed(response, request_id):
    var sword = response as Sword
    if sword:
        print("Received sword: ", sword.sword_name)
        print("Description: ", sword.description)
        print("Materials: ", sword.blade_material, ", ", sword.hilt_material)        
```

## Providers

GodoLM currently supports Mistral and OpenRouter. I am primarily using the MistralProvider in my project so it is the provider that has seen the most testing.
