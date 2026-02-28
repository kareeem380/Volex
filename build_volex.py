import subprocess
import os

def build_volex():
    print("🚀 Starting Volex Build Process...")
    
    # Configuration
    project_path = "Velox.xcodeproj"
    scheme = "Velox"
    configuration = "Release"
    derived_data_path = "build"
    
    # 1. Clean and Build
    cmd = [
        "xcodebuild",
        "-project", project_path,
        "-scheme", scheme,
        "-configuration", configuration,
        "-derivedDataPath", derived_data_path,
        "build"
    ]
    
    try:
        subprocess.run(cmd, check=True)
        print("\n✅ Build Succeeded!")
        
        # 2. Locate the App bundle
        app_path = os.path.join(derived_data_path, "Build/Products/Release/Velox.app")
        if os.path.exists(app_path):
            print(f"\n📦 Artifact generated: {os.path.abspath(app_path)}")
            print("You can move this .app to your /Applications folder.")
        else:
            print("\n❌ Error: Could not find the generated .app file.")
            
    except subprocess.CalledProcessError as e:
        print(f"\n❌ Build Failed: {e}")

if __name__ == "__main__":
    build_volex()
