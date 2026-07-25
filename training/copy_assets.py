import shutil
import os

brain_dir = "/Users/shanacoder/.gemini/antigravity-ide/brain/3f3ed34a-13c9-4884-b578-24f1aa116afa"
assets_dir = "/Users/shanacoder/Documents/Byte/assets"

files_to_copy = {
    "cat_paw_emoji_logo_1785001552302.png": "byte_logo.png",
    "byte_architecture_sketch_1785001284709.png": "byte_architecture_sketch.png",
    "byte_ml_pipeline_sketch_1785001298280.png": "byte_ml_pipeline_sketch.png",
}

for src_name, dst_name in files_to_copy.items():
    src_path = os.path.join(brain_dir, src_name)
    dst_path = os.path.join(assets_dir, dst_name)
    if os.path.exists(src_path):
        with open(src_path, "rb") as f_src:
            data = f_src.read()
        with open(dst_path, "wb") as f_dst:
            f_dst.write(data)
        print(f"Copied {src_name} -> {dst_path} ({len(data)} bytes)")
    else:
        print(f"Source not found: {src_path}")
