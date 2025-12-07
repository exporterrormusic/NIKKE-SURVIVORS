@tool
extends EditorScript
## Run this script from the Script Editor via File > Run (Ctrl+Shift+X)
## to generate the ResourceManifest before exporting.

func _run() -> void:
	print("=" .repeat(60))
	print("Generating Resource Manifest for Export...")
	print("=" .repeat(60))
	
	# Force regeneration
	ResourceManifest.generate_manifest()
	
	print("=" .repeat(60))
	print("Resource Manifest generation complete!")
	print("You can now export the project.")
	print("=" .repeat(60))
