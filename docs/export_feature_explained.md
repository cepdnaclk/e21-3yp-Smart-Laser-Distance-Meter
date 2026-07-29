# PDF & DXF Export — How It Works (Simple Explanation)

---

## The Big Picture

The SmartMeasure app lets users draw floor plans (rooms, doors, windows, furniture) on their phone.
Once drawn, they can export that plan in two formats:

| Format | What it is | Who uses it |
|--------|-----------|-------------|
| **PDF** | A printable document with pages | Anyone (share, print) |
| **DXF** | A CAD file (AutoCAD format) | Engineers, architects |

Both exports read the **same data model** (`SketchShape`) — rooms, their wall points, doors/windows (`RoomObject`), and furniture (`FurnitureItem`).

---

## Part 1 — PDF Export (`sketch/sketch_pdf_export.dart`)

### How a PDF is built

Flutter doesn't have a built-in PDF generator, so we use the **`pdf` package**.
It works like HTML/CSS — you describe widgets (columns, rows, text, containers) and the library renders them into a PDF file.

For drawing custom shapes (walls, doors, furniture) we use **`CustomPaint`** — you get a graphics canvas and draw lines, arcs, and fills directly.

### Coordinate system challenge

The app stores room corners as pixel positions on the phone screen.
PDF uses its own unit called "points" (1 pt ≈ 0.35 mm).
So we need a **coordinate transformer (`_Tx`)** that:

1. Finds the bounding box of all points (min/max X and Y)
2. Scales everything to fit inside the canvas box (296 × 296 pt)
3. Flips the Y-axis (screen Y goes down, PDF Y goes up)

```
PDF point = margin + (worldX - minX) × scale
PDF Y     = canvasSize - margin - (worldY - minY) × scale   ← Y flip
```

### What each page contains

```
Page 1 — Cover / Index
  • Project name, date, stats (room count, total area, total pages)
  • Table of contents with page numbers

Page 2 — Full Overview
  • One canvas showing ALL rooms with coloured fills
  • Doors, windows, furniture drawn on top (added in the final update)
  • Room index table (name, perimeter, area)

Pages 3+ — One page per room
  • Zoomed-in canvas of just that room
  • Walls, corner dots, doors/windows, furniture
  • Stats bar (walls, perimeter, area, height)
  • Doors & windows table (type, width, height, elevation)
  • Furniture table (name, width, depth)
  • Wall measurements table
```

### How doors are drawn in PDF

A door is a **3-line symbol**:

1. A white gap line (erases the wall so the opening is visible)
2. A door-leaf line (hinge → open position, 90° into room)
3. A quarter-circle arc (shows the door swing path)

We calculate the **inward direction** (which way is "into the room") using the centroid of the room — the door always swings toward the room centre.

### How windows are drawn in PDF

A window is **3 parallel lines** across the wall opening:
- A white gap (erases the wall)
- Three blue parallel lines (standard architectural window symbol)

### How furniture is drawn in PDF

Each furniture item has a position, width, depth, and rotation angle.
We rotate its 4 corners using basic trigonometry (cos/sin), transform them into PDF space, and draw:
- A filled rectangle (light colour based on the furniture type's colour)
- A border
- Two diagonal cross lines (standard floor-plan furniture symbol)

---

## Part 2 — DXF Export (`screens/dxf_exporter.dart`)

### What is DXF?

DXF (Drawing Exchange Format) is a plain **text file** that AutoCAD and other CAD tools understand.
It is a list of "group codes" (numbers) followed by values, like:

```
  0
LINE
  8
WALLS
 10
100.0000
 20
-200.0000
```

This means: "draw a LINE on layer WALLS starting at X=100, Y=-200 …"

There is no library needed — we just write this text ourselves using a `StringBuffer`.

### Layers

The DXF file organises elements into **layers** (like Photoshop layers), each with a colour:

| Layer | Colour | Contains |
|-------|--------|----------|
| WALLS | Blue | Room wall outlines + wall dimension labels |
| DOORS | Red | Door leaf lines, arc, dimension |
| WINDOWS | Cyan | Window parallel lines, dimension |
| FURNITURE | Green | Furniture rectangles + name labels |
| ROOM_NAMES | Yellow | Room name text at room centre |

### Coordinate system

The app uses screen pixels (Y going down).
DXF uses millimetres with Y going up.
So we apply two transformations:

```
DXF X = worldX × 5        (1 world unit = 5 mm)
DXF Y = -(worldY × 5)     (flip Y axis)
```

### Wall dimensions

For each wall we:
1. Find the wall midpoint
2. Calculate which side faces **outward** (away from room centroid)
3. Place a dimension line 80 mm outside the wall
4. Add extension lines at both ends
5. Write the real measured length (from the device) or the drawn length if not measured

### Door in DXF

Same logic as PDF but written as DXF entities:
- `LINE` for the door leaf (hinge to open tip)
- `LINE` for the door frame (hinge to far jamb)
- `ARC` for the swing path
- Dimension lines + text showing width

### Window in DXF

- 3 parallel `LINE` entities across the opening (at -55, 0, +55 mm offset)
- 2 short `LINE` entities as jamb markers at each end
- Dimension lines + text showing width

### Furniture in DXF

- 4 corner points calculated using cos/sin rotation
- 4 `LINE` entities forming the rectangle border
- 2 diagonal `LINE` entities (X cross)
- `TEXT` entity with the furniture name at the centre

### File delivery

The DXF text is written to a **temporary file** on the phone, then shared using the `share_plus` package — the user can send it via email, save to files, etc.

---

## Summary — Key Concepts Used

| Concept | Where used |
|---------|-----------|
| Coordinate transformation (scale + Y-flip) | Both PDF and DXF |
| Centroid calculation | Finding inward wall direction for doors/windows |
| Trigonometry (cos/sin) | Rotating furniture corners; door arc angles |
| StringBuffer text generation | DXF file building |
| `pdf` package CustomPaint | PDF canvas drawing |
| Layers | DXF organisation |
| `share_plus` | Sharing the exported DXF file |
| `printing` package | PDF preview/print/share dialog |

---

*Generated for SmartMeasure — 3YP, University of Peradeniya*
