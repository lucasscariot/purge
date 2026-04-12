# 🎨 Tactile Scrapbook: Design System & Style Guide

Welcome to the **Tactile Scrapbook** design system. This document serves as the single source of truth for designers and developers to maintain our polished, playful, and physical-feeling app UI.

## 1. Core Philosophy
The core of this aesthetic relies on bridging the digital and physical worlds. It should feel like a premium, handcrafted notebook filled with glossy vinyl stickers, heavy textured paper, and tactile feedback.
- **Physicality over Flatness:** Elements should have weight, texture, and depth.
- **Playful but Polished:** Use playful elements (stickers, scattered cards) but ground them with elegant typography and subdued, sophisticated colors.
- **Micro-tactile:** Every interaction should feel satisfying, leveraging subtle animations and haptic feedback.

---

## 2. Color Palette

Our palette moves away from stark digital primaries and embraces earthy, muted pastels that mimic dyed paper.

### Base / Backgrounds
- **Cream / Off-White:** `#FAF8F5` (Use for main app backgrounds)
- **Charcoal (Text):** `#2D2B2A` (Never use pure black `#000000`)
- **Muted Grey (Subtext):** `#8C8A88`
- **Dot Grid Grey:** `#E5E3E0` (Used specifically for the notebook dots)

### Card / Accent Colors (Earthy Pastels)
These colors are used for the memory cards, tags, and large color-block areas.
- **Mustard Yellow:** `#EBC464`
- **Dusty Rose / Coral:** `#E76F68`
- **Sage Green:** `#A6BE88`
- **Lavender / Periwinkle:** `#B4A5D7`
- **Soft Peach:** `#E5B8AD`

*Developer Note:* Export these as CSS variables or an iOS/Android Color Asset Catalog.

---

## 3. Typography

The typographic contrast is crucial: we pair an elegant, editorial Serif with a modern, highly-legible Sans-Serif.

### Display / Headers (Serif)
Used for Page Titles (like Dates), Card Fronts, and large numbers.
- **Font Family:** `Playfair Display`, `GT Super`, or `Libre Baskerville`
- **Weight:** Bold / Semi-Bold
- **Tracking:** Tight (-2%)

### UI / Body / Subtitles (Sans-Serif)
Used for UI labels, sticker text, word translations, small metadata, and buttons.
- **Font Family:** `SF Pro Rounded`, `Inter`, or `Nunito`
- **Weight:** Medium / Bold / Black (for bold sticker labels)
- **Tracking:** Normal or slightly wide (1%) for small caps.

---

## 4. Textures & Materials

This is what gives the app its "Scrapbook" feel. Avoid solid vector fills without texture or context.

### 4.1 The Dot Grid Notebook Background (Central View Style)
The primary canvas of the app should mimic a high-quality dotted notebook (bullet journal). 
- **Background Color:** Cream / Off-White (`#FAF8F5`)
- **The Grid:** A repeating pattern of small dots.
  - **Dot Color:** Muted, translucent grey (`#E5E3E0` or `rgba(0,0,0,0.05)`)
  - **Dot Size:** `2px` to `3px`
  - **Spacing:** Roughly `24px` to `32px` apart
- **Implementation (CSS/SwiftUI):** Use a repeating background image, a patterned color asset, or a programmatic dot grid drawn on the canvas.

### 4.2 The "Speckled" Paper Texture
Cards and colored backgrounds must have a subtle noise/speckle overlay.
- **Implementation:** Use an SVG noise filter or a seamless repeating `.png` with small, sparse dots (terrazzo style).
- **Blend Mode:** `Multiply` or `Color Burn` at `5% - 12%` opacity depending on the background color.

### 4.3 Shadows & Depth
Shadows should feel like diffused, natural lighting on a desk, not harsh digital dropshadows.
- **High Float (Overlapping Cards):** `box-shadow: 0px 12px 32px rgba(0, 0, 0, 0.08);`
- **Low Float (Stickers):** `box-shadow: 0px 4px 12px rgba(0, 0, 0, 0.12);`

---

## 5. Core UI Components

### 5.1 The Scrapbook Page (Central View)
This is the main interaction area where the user views their items.
- **Canvas:** Uses the **Dot Grid Notebook Background**.
- **Layout:** Freeform and organic. Stickers should not feel locked into a rigid grid. They can stagger, float at different heights, and have varying alignments to feel "placed by hand".
- **Headers:** Dates and main titles float cleanly over the dot grid in the Serif font.

### 5.2 "Die-Cut" Stickers (Images + Labels)
Photographic assets and their text labels must ALWAYS be treated as physical, unified vinyl stickers.
1. **Asset:** High-quality photo with background completely removed (transparent PNG/WebP).
2. **Text Label:** The identifying text (e.g., "Бананы", "Кружка") is placed directly overlapping the bottom of the image. It uses a heavy, rounded Sans-Serif font in the Charcoal color.
3. **The Vinyl Cut (White Stroke):** A thick, continuous, solid white outline wraps around *both* the image and the text label, unifying them into a single physical object. 
   - *Implementation:* Use a prominent white stroke/outline or drop-shadow on the combined group.
4. **Shadow:** Apply the "Low Float" shadow underneath the entire white sticker shape.

### 5.3 Memory Cards
- **Border Radius:** Very soft squircles (e.g., `border-radius: 24px` to `32px` depending on screen size).
- **Background:** One of the Accent Colors + Speckled Texture overlay.
- **Layout:** When showing multiple cards, apply slight rotations (`-3deg` to `+3deg`) to make them feel "tossed" onto the screen.

---

## 6. Motion & Haptics

Animations and device haptics are what sell the "tactile" illusion.

### 6.1 Animations (Spring Physics)
Avoid linear or simple ease-in-out animations. Use Spring physics so elements have a slight "bounce" or "snap" when settling into place.
- **Stiffness:** High
- **Damping:** Medium-Low (allow a small wobble)

### 6.2 Haptic Feedback Matrix
Trigger device haptic motors on these specific events:
- **Card Swipe / Deck Advance:** `Light` haptic tap.
- **Dragging a Sticker:** Continuous `Very Light` ticking (if supported) or a single `Light` tap on pickup.
- **Dropping a Sticker / Placing an Item:** `Medium` haptic thump.
- **Success / Completing a Daily Goal:** `Success` / `Heavy` haptic pattern.
*(iOS: `UIImpactFeedbackGenerator` | Android: `HapticFeedbackConstants`)*

---

## 7. Asset Creation Pipeline (For Content Creators)

When adding new vocabulary words or items to the app:
1. Source a brightly lit, high-resolution photo of the object.
2. Remove the background perfectly (no fringing).
3. Apply image adjustments: Boost vibrance slightly, increase contrast to make it "pop" on screen.
4. Add a `12px` - `16px` pure white stroke around the exact contour of the object and its accompanying text label to create the "sticker" effect.
5. Export as `WebP` (for mobile performance) with alpha transparency.