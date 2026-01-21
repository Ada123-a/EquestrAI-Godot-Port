from PIL import Image, ImageDraw

def draw_unicorn_horn(draw, fill_color, outline_color, ridge_color):
    # Shape: A diagonal cone pointing to (0,0).
    # Tip at (0, 0).
    
    # Cone Points
    tip = (0, 0)
    base_l = (8, 24)
    base_r = (24, 8)
    
    # Main Horn Triangle
    horn_points = [tip, base_l, base_r]
    
    draw.polygon(horn_points, fill=fill_color, outline=outline_color)
    
    # Ridges
    # Use a loop to draw lines
    for i in range(1, 4):
        # Edge 1 point at fraction t
        t = i * 0.25
        p1_x = 0 + (8 - 0) * t
        p1_y = 0 + (24 - 0) * t
        
        p2_x = 0 + (24 - 0) * t
        p2_y = 0 + (8 - 0) * t
        
        # Draw curve/line
        draw.line([(p1_x, p1_y), (p2_x, p2_y)], fill=outline_color, width=1)
        
    # Outline re-stroke to be clean
    draw.line([tip, base_l], fill=outline_color, width=1)
    draw.line([tip, base_r], fill=outline_color, width=1)
    # Base curve - emulate with slightly curved line
    draw.line([base_l, base_r], fill=outline_color, width=1)


def create_arrow(filename):
    # Regular Unicorn Horn
    size = (32, 32)
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Color: Lavender (Twilightish)
    fill_color = "#D19FE3" 
    outline_color = "#241842"
    ridge_color = "#B76FD6" 
    
    draw_unicorn_horn(draw, fill_color, outline_color, ridge_color)
    
    img.save(filename)
    print(f"Saved {filename}")

def create_hand(filename):
    # Magic Aura Unicorn Horn
    size = (32, 32)
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Magic Aura Color (Twilight Magic - Magenta/Pink)
    aura_color = "#FA5FE3" 
    
    # Draw Aura first (Expanded triangle)
    # Tip at (-2, -2)? No, just offset out.
    # We can simulate glow by drawing 4 copies offset by 1 pixel?
    # Or just a larger polygon.
    
    # Larger polygon points
    # Tip at (-2,-2) clipped? 
    # Hotspot is (0,0), so visuals must start at (0,0) or (1,1).
    
    # If the Arrow is at (0,0), we want the Aura to surround it, meaning the physical pixels might go to (-1,-1) which is impossible.
    # To fix this, we should shift BOTH cursors slightly so the "Tip" is at (2,2).
    # Then we can draw aura at (0,0).
    # But that requires updating the Hotspot in Godot to (2,2).
    
    # Let's adjust the draw_unicorn_horn to accept an offset.
    
    # Re-defining the draw helper locally for the shift logic would be cleaner but let's just do it manually here.
    
    # --- OFFSET LOGIC ---
    # We will offset ONLY the Hand cursor logic? No, Arrow should match position if possible, but shift is fine.
    # Actually, simpler: Use the same (0,0) tip for arrow. 
    # For aura, just draw it behind the best we can. 
    # We can draw the aura going Right and Down. The top-left part of the aura will just be the tip itself (which is colored magic).
    
    # Let's try coloring the Tip itself with Aura color?
    # No, distinct "Glow" is requested.
    
    # Let's Shift base horn to (2,2).
    start_x, start_y = 2, 2
    
    # Draw Aura Polygon (Larger)
    # Tip at (0,0)
    # Base L at (9, 27)
    # Base R at (27, 9)
    draw.polygon([(0,0), (10, 28), (28, 10)], fill=aura_color)
    
    # Draw "Glow" soft bits
    draw.polygon([(0,0), (8, 24), (24, 8)], fill=aura_color)
    # It's an aura, a blob.
    # Draw lines around the future horn position.
    
    # Now draw the Horn on top, shifted to (2,2)
    offset_x, offset_y = 2, 2
    
    fill_color = "#D19FE3" 
    outline_color = "#241842"
    
    tip = (offset_x, offset_y)
    base_l = (offset_x + 8, offset_y + 24)
    base_r = (offset_x + 24, offset_y + 8)
    
    horn_points = [tip, base_l, base_r]
    draw.polygon(horn_points, fill=fill_color, outline=outline_color)
    
    # Ridges (shifted)
    for i in range(1, 4):
        t = i * 0.25
        p1_x = offset_x + (8 * t)
        p1_y = offset_y + (24 * t)
        p2_x = offset_x + (24 * t)
        p2_y = offset_y + (8 * t)
        draw.line([(p1_x, p1_y), (p2_x, p2_y)], fill=outline_color, width=1)

    draw.line([tip, base_l], fill=outline_color, width=1)
    draw.line([tip, base_r], fill=outline_color, width=1)
    draw.line([base_l, base_r], fill=outline_color, width=1)
    
    # Add some "sparkles" for the magic effect?
    # Small dots around
    draw.point([(20, 2), (25, 4), (2, 20)], fill=aura_color)
    
    img.save(filename)
    print(f"Saved {filename}")
    
    # Save copy as mlp_select.png so we have a dedicated selection cursor file
    if "mlp_hand.png" in filename:
        select_name = filename.replace("mlp_hand.png", "mlp_select.png")
        img.save(select_name)
        print(f"Saved {select_name}")

# We need to redefine Create Arrow to optionally shift too or keep at 0,0.
# If we shift arrow to (2,2), we must update Godot hotspot.
# To keep it consistent between states, let's shift Arrow too.

def create_arrow_shifted(filename):
    size = (32, 32)
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    fill_color = "#D19FE3" 
    outline_color = "#241842"
    
    offset_x, offset_y = 2, 2
    
    tip = (offset_x, offset_y)
    base_l = (offset_x + 8, offset_y + 24)
    base_r = (offset_x + 24, offset_y + 8)
    
    horn_points = [tip, base_l, base_r]
    draw.polygon(horn_points, fill=fill_color, outline=outline_color)
    
    # Ridges
    for i in range(1, 4):
        t = i * 0.25
        p1_x = offset_x + (8 * t)
        p1_y = offset_y + (24 * t)
        p2_x = offset_x + (24 * t)
        p2_y = offset_y + (8 * t)
        draw.line([(p1_x, p1_y), (p2_x, p2_y)], fill=outline_color, width=1)

    draw.line([tip, base_l], fill=outline_color, width=1)
    draw.line([tip, base_r], fill=outline_color, width=1)
    draw.line([base_l, base_r], fill=outline_color, width=1)

    img.save(filename)
    print(f"Saved {filename}")

# Overwriting original creating logic
create_arrow = create_arrow_shifted

def create_busy_frames(filename_base_pattern):
    # Generates busy_1, busy_2
    size = (32, 32)
    center = (16, 16)
    radius_outer = 13
    radius_inner = 5
    import math
    
    # Two frames: 0 and 30 degrees (since it's 6 points, 60 deg symmetry, 30 deg is half-way)
    frames = [0, 30] 
    
    for idx, rot_offset in enumerate(frames):
        img = Image.new('RGBA', size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        
        points = []
        for i in range(12):
            # 12 points (6 outer, 6 inner)
            # 360 / 12 = 30 degrees per step.
            angle_deg = (i * 30) + rot_offset - 90 # -90 to start at top
            angle = angle_deg * (math.pi / 180)
            
            r = radius_outer if i % 2 == 0 else radius_inner
            x = center[0] + r * math.cos(angle)
            y = center[1] + r * math.sin(angle)
            points.append((x, y))
            
        # Twilight Star: Magenta/Pink with white outline
        draw.polygon(points, fill="#D35E99", outline="#FFFFFF")
        
        fname = filename_base_pattern.replace("*", str(idx + 1))
        img.save(fname)
        print(f"Saved {fname}")

def create_ibeam(filename):
    size = (32, 32)
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Simple I-Beam
    color = "#99D9EA" # Dash Cyan (Matches Move Icon)
    
    # Top bar
    draw.line([(10, 4), (22, 4)], fill=color, width=2)
    # Bottom bar
    draw.line([(10, 28), (22, 28)], fill=color, width=2)
    # Vertical
    draw.line([(16, 4), (16, 28)], fill=color, width=2)
    
    img.save(filename)
    print(f"Saved {filename}")

def create_move(filename):
    size = (32, 32)
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    color = "#99D9EA" # Dash Cyan
    outline = "#2F6B80"
    
    # Just standard shape
    # N
    pts_n = [(16,2), (12,8), (14,8), (14,14), (18,14), (18,8), (20,8)]
    draw.polygon(pts_n, fill=color, outline=outline)
    
    # S
    pts_s = [(16,30), (12,24), (14,24), (14,18), (18,18), (18,24), (20,24)]
    draw.polygon(pts_s, fill=color, outline=outline)
    
    # W
    pts_w = [(2,16), (8,12), (8,14), (14,14), (14,18), (8,18), (8,22)]
    draw.polygon(pts_w, fill=color, outline=outline)
    
    # E
    pts_e = [(30,16), (24,12), (24,14), (18,14), (18,18), (24,18), (24,22)]
    draw.polygon(pts_e, fill=color, outline=outline)

    img.save(filename)
    print(f"Saved {filename}")

if __name__ == "__main__":
    import os
    out_dir = r"assets/UI/Cursors/MLP"
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)
        
    create_arrow(os.path.join(out_dir, "mlp_arrow.png"))
    create_hand(os.path.join(out_dir, "mlp_hand.png"))
    create_busy_frames(os.path.join(out_dir, "mlp_busy_*.png"))
    create_ibeam(os.path.join(out_dir, "mlp_ibeam.png"))
    create_move(os.path.join(out_dir, "mlp_move.png"))
