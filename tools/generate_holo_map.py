# tools/generate_holo_map.py
import urllib.request
import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

def generate_holographic_world_map():
    url = "https://raw.githubusercontent.com/datasets/geo-countries/master/data/countries.geojson"
    print("Fetching Natural Earth GeoJSON data...")
    req = urllib.request.urlopen(url, timeout=20)
    data = json.loads(req.read().decode('utf-8'))
    print(f"Loaded {len(data['features'])} country geometries.")

    # High-definition 16:9 canvas
    width = 2048
    height = 1152

    # Map projection matching user mockup
    # Longitude: -175.0 to 190.0 (span 365)
    min_lng = -175.0
    max_lng = 190.0
    lng_span = max_lng - min_lng

    def miller_y(lat):
        lat_rad = math.radians(max(min(lat, 82.0), -65.0))
        return 1.25 * math.log(math.tan(0.25 * math.pi + 0.4 * lat_rad))

    y_max = miller_y(82.0)
    y_min = miller_y(-65.0)
    y_span = y_max - y_min

    def project(lng, lat):
        norm_x = (lng - min_lng) / lng_span
        norm_y = (y_max - miller_y(lat)) / y_span
        return (norm_x * width, norm_y * height)

    # 1. Generate Polygon Land Mask
    print("Rasterizing geographic polygons to high-res mask...")
    land_mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(land_mask)

    for feature in data['features']:
        geom = feature['geometry']
        gtype = geom['type']
        coords = geom['coordinates']

        if gtype == 'Polygon':
            polys = [coords]
        elif gtype == 'MultiPolygon':
            polys = coords
        else:
            continue

        for poly in polys:
            for ring in poly:
                pts = [project(pt[0], pt[1]) for pt in ring]
                if len(pts) >= 3:
                    mask_draw.polygon(pts, fill=255)

    print("Generating holographic layers...")
    output_img = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    # Layer A: Semi-transparent dark navy land body (#071426)
    land_body = Image.new("RGBA", (width, height), (7, 20, 38, 140))
    output_img.paste(land_body, (0, 0), land_mask)

    # Layer B: Outer Cyan Coastline Glow (00D2FF)
    coast_edges = land_mask.filter(ImageFilter.FIND_EDGES)
    
    # Wide soft glow
    outer_glow_mask = coast_edges.filter(ImageFilter.GaussianBlur(radius=5))
    outer_glow = Image.new("RGBA", (width, height), (0, 180, 255, 140))
    output_img.paste(outer_glow, (0, 0), outer_glow_mask)

    # Medium vibrant glow
    mid_glow_mask = coast_edges.filter(ImageFilter.GaussianBlur(radius=2))
    mid_glow = Image.new("RGBA", (width, height), (0, 229, 255, 200))
    output_img.paste(mid_glow, (0, 0), mid_glow_mask)

    # Crisp sharp core edge
    core_edge = Image.new("RGBA", (width, height), (120, 245, 255, 255))
    output_img.paste(core_edge, (0, 0), coast_edges)

    # Layer C: Dense Cyber Dot-Matrix inside land
    print("Synthesizing cyber dot-matrix...")
    dot_spacing = 6
    dot_radius = 1.3
    dot_canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    dot_draw = ImageDraw.Draw(dot_canvas)

    # Fast pixel access
    mask_pixels = land_mask.load()

    for y in range(0, height, dot_spacing):
        for x in range(0, width, dot_spacing):
            val = mask_pixels[x, y]
            if val > 100:
                # Slight variation in brightness for topographic depth
                alpha = int(180 + 70 * (math.sin(x * 0.05) * math.cos(y * 0.05)))
                dot_draw.ellipse(
                    [x - dot_radius, y - dot_radius, x + dot_radius, y + dot_radius],
                    fill=(56, 189, 248, alpha)
                )

    output_img = Image.alpha_composite(output_img, dot_canvas)

    # Save to assets/images/world_map_holo.png
    out_dir = r"d:\OneDrive\客戶端開發\assets\images"
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "world_map_holo.png")
    output_img.save(out_path, "PNG", optimize=True)
    print(f"Holographic world map generated successfully at: {out_path} ({os.path.getsize(out_path)} bytes)")

if __name__ == "__main__":
    generate_holographic_world_map()
