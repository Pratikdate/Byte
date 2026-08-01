import argparse
import os
import sys
from huggingface_hub import HfApi, create_repo, login

def upload_byte_model(repo_id, token=None):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    model_dir = os.path.join(script_dir, "byte_fused_model")
    
    if not os.path.exists(model_dir):
        print(f"❌ Error: Fused model directory '{model_dir}' not found. Please run training first.")
        sys.exit(1)
        
    api = HfApi()
    
    if token:
        login(token=token)
        
    print(f"🚀 Preparing to upload Byte open-source model weights to Hugging Face Hub: {repo_id}...")
    
    try:
        create_repo(repo_id=repo_id, repo_type="model", exist_ok=True)
        print(f"✅ Repository '{repo_id}' ready on Hugging Face.")
    except Exception as e:
        print(f"⚠️ Notice regarding repo creation: {e}")
        
    print(f"📦 Uploading files from {model_dir}...")
    api.upload_folder(
        folder_path=model_dir,
        repo_id=repo_id,
        repo_type="model"
    )
    
    print(f"
🎉 SUCCESS! Byte open-source model weights published to:
👉 https://huggingface.co/{repo_id}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upload Byte Model Weights to Hugging Face Hub")
    parser.add_argument("--repo-id", required=True, help="Hugging Face Repo ID (e.g. username/Byte-Desktop-Pet-1B)")
    parser.add_argument("--token", help="Hugging Face User Access Token (optional if logged in via huggingface-cli)")
    args = parser.parse_args()
    
    upload_byte_model(repo_id=args.repo_id, token=args.token)
