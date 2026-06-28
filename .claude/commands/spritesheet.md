# Spritesheet Builder

Build a spritesheet from individual PNG frames using Python + Pillow. Handles frame sequencing, bottom-alignment across frames with different content heights, and transparent background removal.

## Steps

### 1. Read and verify the source frames

Read each source image before building so you can confirm the frames and their content visually.

```python
from PIL import Image
frames = ['Frame1.png', 'Frame2.png', 'Frame3.png']  # adjust names
for name in frames:
    img = Image.open(f'{source_dir}/{name}.png')
    # Read via the Read tool to visually confirm each frame
```

### 2. Remove the white background on each source frame (make transparent)

Do this on the source frames first — once the background is transparent, finding the content bottom in the next step becomes a simple alpha check with no need for a background color or pixel threshold.

Use a two-pass approach on each source frame:

1. **Edge flood fill** — clears the exterior background without touching white pixels inside the character (highlights, eyes, etc.)
2. **Blanket pass** — clears any remaining pure-white pixels that were enclosed (e.g. trapped under arms) and unreachable from the edges

```python
from PIL import Image
from collections import deque

def remove_background(path, bg_color=(255, 255, 255, 255)):
    img = Image.open(path).convert('RGBA')
    pixels = img.load()
    w, h = img.size

    # Pass 1: edge flood fill to remove exterior background
    visited = [[False] * h for _ in range(w)]
    queue = deque()
    for x in range(w):
        for y in [0, h - 1]:
            if pixels[x, y] == bg_color and not visited[x][y]:
                queue.append((x, y))
                visited[x][y] = True
    for y in range(h):
        for x in [0, w - 1]:
            if pixels[x, y] == bg_color and not visited[x][y]:
                queue.append((x, y))
                visited[x][y] = True
    while queue:
        x, y = queue.popleft()
        pixels[x, y] = (0, 0, 0, 0)
        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not visited[nx][ny] and pixels[nx, ny] == bg_color:
                visited[nx][ny] = True
                queue.append((nx, ny))

    # Pass 2: blanket clear of any remaining enclosed background pixels
    # Safe to do now — exterior is already gone, so only trapped pixels remain
    for y in range(h):
        for x in range(w):
            if pixels[x, y] == bg_color:
                pixels[x, y] = (0, 0, 0, 0)

    img.save(path)

for name in unique_frame_names:
    remove_background(f'{source_dir}/{name}.png')
```

### 3. Find the true content bottom of each frame

With the background now transparent, this is a simple alpha scan — any pixel with alpha > 0 is character content.

```python
from PIL import Image

def get_content_bottom(path):
    img = Image.open(path).convert('RGBA')
    pixels = img.load()
    w, h = img.size
    char_bottom = 0
    for y in range(h):
        if any(pixels[x, y][3] > 0 for x in range(w)):
            char_bottom = y
    return char_bottom
```

### 4. Build the bottom-aligned spritesheet

Align all frames so their content bottoms land on the same pixel row, then stitch them horizontally. The sequence can be any length — use repeated and mirrored frames to create smooth loops.

```python
from PIL import Image

source_dir = r'path/to/frames'
output_path = r'path/to/output/spritesheet.png'

# Define frame sequence — any number of frames, repeat/mirror as needed.
# Examples:
#   Simple loop:       ['A', 'B', 'C', 'D']
#   Ping-pong loop:    ['A', 'B', 'C', 'D', 'C', 'B']
#   Hold on key frame: ['A', 'B', 'C', 'C', 'C', 'B', 'A']
sequence = ['Frame1', 'Frame2', 'Frame3', 'Frame2', 'Frame1']

# Measure content bottoms (background already transparent from step 2)
bottoms = {}
for name in set(sequence):
    img = Image.open(f'{source_dir}/{name}.png').convert('RGBA')
    pixels = img.load()
    w, h = img.size
    cb = 0
    for y in range(h):
        if any(pixels[x, y][3] > 0 for x in range(w)):
            cb = y
    bottoms[name] = cb

target_bottom = max(bottoms.values())

# Get frame dimensions from first image
fw, fh = Image.open(f'{source_dir}/{sequence[0]}.png').size

# Build sheet with transparent background
sheet = Image.new('RGBA', (fw * len(sequence), fh), (0, 0, 0, 0))
for i, name in enumerate(sequence):
    img = Image.open(f'{source_dir}/{name}.png').convert('RGBA')
    shift = target_bottom - bottoms[name]
    frame = Image.new('RGBA', (fw, fh), (0, 0, 0, 0))
    frame.paste(img, (0, shift))
    sheet.paste(frame, (i * fw, 0))

sheet.save(output_path)
```

## Notes

- **Background color**: flood fill assumes pure white `(255, 255, 255, 255)`. Change `bg_color` if the source images use a different background.
- **Frame sequence length**: sequences can be any length. Longer sequences allow more expressive animations — hold frames, eases, reaction beats, etc.
- **Ping-pong loops**: mirroring frames (`A B C D C B`) avoids a jump cut when the animation loops without needing duplicate art.
- **Sync to game project**: after saving, copy the spritesheet into the game's asset folder (e.g. `parsec/assets/sprites/`).
