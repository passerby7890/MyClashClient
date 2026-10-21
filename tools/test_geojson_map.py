# tools/test_geojson_map.py
import urllib.request
import json
import math
from PIL import Image, ImageDraw, ImageFilter

def download_and_render():
    url = "https://raw.githubusercontent.com/datasets/geo-countries/master/data/countries.geojson"
    print("Downloading GeoJSON...")
    req = urllib.request.urlopen(url, timeout=15)
    data = json.loads(req.read().decode('utf-8'))
    print(f"Loaded {len(data['features'])} countries.")

    width = 2048
    height = 1144 # 16:9 approx
    
    # Let's create an RGBA image
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Equirectangular projection mapping
    # Longitude: -180 to 180 -> 0 to width
    # Latitude: 85 to -60 -> 0 to height (crop polar regions for beautiful aspect ratio)
    min_lat = -60.0
    max_lat = 85.0
    
    def project(lng, lat):
        x = (lng + 180.0) / 360.0 * width
        y = (max_lat - lat) / (max_lat - min_lat) * height
        return (x, y)

    # First draw polygons to a mask
    mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)

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

    print("Mask created. Rendering glowing coastlines and dot matrix...")
    
    # 1. Base dark fill on land
    land_fill = Image.new("RGBA", (width, height), (15, 30, 55, 120))
    img.paste(land_fill, (0, 0), mask)

    # 2. Glowing coastlines:
    # Outer glow (expanded mask - mask, blurred)
    edges = mask.filter(ImageFilter.FIND_EDGES)
    outer_glow = edges.filter(ImageFilter.GaussianBlur(radius=3))
    
    glow_color = Image.new("RGBA", (width, height), (0, 210, 255, 180))
    img.paste(glow_color, (0, 0), outer_glow)

    core_edges = Image.new("RGBA", (width, height), (70, 230, 255, 240))
    img.paste(core_edges, (0, 0), edges)

    # 3. Fine Dot-Matrix inside land mask
    dot_spacing = 6
    dot_radius = 1.2
    dot_img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    dot_draw = ImageDraw.Draw(dot_img)

    for y in range(0, height, dot_spacing):
        for x in range(0, width, dot_spacing):
            if mask.getpixel((x, y)) > 128:
                dot_draw.ellipse(
                    [x - dot_radius, y - dot_radius, x + dot_radius, y + dot_radius],
                    fill=(56, 189, 248, 220)
                )

    img = Image.alpha_composite(img, dot_img)
    
    out_file = r"d:\OneDrive\客戶端開發\assets\images\world_map_holo.png"
    img.save(out_file, "PNG")
    print(f"Saved {out_file} successfully! Size: {os.path.getsize(out_file)} bytes")

if __name__ == "__main__":
    import os
    download_and_render()
