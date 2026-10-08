"""Assembles PNG frame folders from render_gifs.swift into tight-cropped GIFs
on a white background. Usage: make_gifs.py <frames_dir> <out_dir>"""
import os, sys
from PIL import Image

frames_dir, out_dir = sys.argv[1:3]
# scene -> (gif name, ms per frame)
OUT = {"hammer": ("hammer", 300), "canvas": ("canvas", 250), "agents": ("agents", 100)}
PAD = 24

for scene in sorted(os.listdir(frames_dir)):
    files = sorted(f for f in os.listdir(os.path.join(frames_dir, scene)) if f.endswith(".png"))
    imgs = [Image.open(os.path.join(frames_dir, scene, f)).convert("RGBA") for f in files]
    # One crop box shared by every frame so the sprite doesn't jitter.
    boxes = [b for b in (im.getchannel("A").getbbox() for im in imgs) if b]
    l = min(b[0] for b in boxes) - PAD; t = min(b[1] for b in boxes) - PAD
    r = max(b[2] for b in boxes) + PAD; btm = max(b[3] for b in boxes) + PAD
    out = []
    for im in imgs:
        # Pad the canvas first: cropping past an edge would fill with black.
        bg = Image.new("RGBA", (im.width + 2 * PAD, im.height + 2 * PAD), "white")
        bg.alpha_composite(im, (PAD, PAD))
        out.append(bg.crop((l + PAD, t + PAD, r + PAD, btm + PAD)).convert("RGB"))
    name, ms = OUT[scene]
    out[0].save(os.path.join(out_dir, name + ".gif"), save_all=True, append_images=out[1:], duration=ms, loop=0, optimize=True)
    print(name, out[0].size, len(out))
