import os
import shutil

assets_dir = "/Users/shanacoder/Documents/Byte/assets"
web_img_dir = "/Users/shanacoder/Documents/Byte/website/static/img"

os.makedirs(web_img_dir, exist_ok=True)

files = ["byte_logo.png", "byte_architecture_sketch.png", "byte_ml_pipeline_sketch.png"]

for filename in files:
    src_path = os.path.join(assets_dir, filename)
    dst_path = os.path.join(web_img_dir, filename)
    if os.path.exists(src_path):
        with open(src_path, "rb") as f_src:
            data = f_src.read()
        with open(dst_path, "wb") as f_dst:
            f_dst.write(data)
        print(f"Copied {filename} -> {dst_path} ({len(data)} bytes)")
    else:
        print(f"File not found: {src_path}")
