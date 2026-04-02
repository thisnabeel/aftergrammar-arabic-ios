# Chapters API Product Doc (Read Endpoints)

Use this as a handoff for building the iOS app read experience.

## Base Assumptions

- API base URL example: `http://localhost:3000`
- JSON over HTTP
- Auth headers (optional for read, but useful):
  - `X-User-Email`
  - `X-User-Token`
- If authenticated as admin, `/chapters/:id` returns all layers (including inactive).
- If unauthenticated/non-admin, `/chapters/:id` returns only active layers.

## 1) Get Chapter Tree by Language

### Route

`GET /languages/:language_id/chapters`

### Example

`GET /languages/1/chapters`

### Purpose

Returns a nested chapter tree for one language (parent/child structure).

### Response shape

```json
{
  "chapters": [
    {
      "id": 10,
      "title": "Chapter Title",
      "description": "Optional text",
      "chapter_id": null,
      "position": 0,
      "language_id": 1,
      "children": [
        {
          "id": 11,
          "title": "Nested Chapter",
          "description": "",
          "chapter_id": 10,
          "position": 0,
          "language_id": 1,
          "children": []
        }
      ]
    }
  ]
}
```

### Field notes

- `chapter_id: null` means top-level chapter
- `children` is recursive nested chapter data
- `position` is sibling order (ascending)

### iOS usage guidance

- Build a hierarchical list/tree UI from `children`
- Indent nested nodes by depth
- Use `position` for ordering among siblings
- Tap chapter row, then call `/chapters/:id`

## 2) Get Chapter Detail + Layers + Items

### Route

`GET /chapters/:id`

### Example

`GET /chapters/4`

### Purpose

Returns chapter metadata, language direction, and layer/item content for rendering.

### Response shape

```json
{
  "chapter": {
    "id": 4,
    "title": "المقدمة",
    "description": "Optional",
    "chapter_id": null,
    "position": 0,
    "language_id": 1
  },
  "language": {
    "id": 1,
    "direction": "rtl"
  },
  "chapter_layers": [
    {
      "id": 20,
      "title": "Main",
      "active": true,
      "is_default": true,
      "position": 0,
      "chapter_layer_items": [
        {
          "id": 301,
          "chapter_layer_id": 20,
          "body": "Some html/text",
          "style": "inline",
          "hint": "Optional hint",
          "position": 0,
          "created_at": "2026-03-23T00:00:00Z",
          "updated_at": "2026-03-23T00:00:00Z"
        }
      ]
    }
  ],
  "viewer_is_admin": false
}
```

### Layer visibility rules

- `viewer_is_admin == true`:
  - receives all layers (`active` true/false)
- non-admin / no auth:
  - receives only `active == true` layers

### Direction

- `language.direction` drives text direction for content rendering
- Use `rtl` for Arabic/Hebrew, fallback to `ltr` if missing

### Layer defaults

- `is_default == true` marks preferred initial tab

## Layer Item Rendering Rules

`chapter_layer_items` are ordered by `position`.

Supported `style` values:

- `inline` -> inline flowing text
- `header` -> heading-like block
- `block` -> paragraph block
- `quote` -> blockquote
- `bullet` -> bullet list row
- `ordered` -> ordered list row
- `line_break` -> visual line break
- `hr` -> horizontal divider

### Suggested rendering mapping

- `inline`: append to running inline flow
- `header`: render as heading-styled text
- `block`: paragraph spacing
- `quote`: inset + leading border
- `bullet`: bullet marker + body
- `ordered`: numbered marker + body
- `line_break`: add spacing/newline
- `hr`: divider view

### Body format

- `body` may contain text or simple HTML
- Safest approach:
  - parse lightweight inline HTML (or strip tags initially)
  - still honor style semantics above

### Hint behavior

- `hint` is optional supplemental text
- Current product behavior: hint shown/toggled separately from main body

## Recommended iOS Flow

1. Call `GET /languages/:id/chapters`
2. Show hierarchical chapter browser
3. On chapter tap call `GET /chapters/:id`
4. Build tabs from `chapter_layers` (default tab from `is_default`)
5. Render selected layer items by `style` + `position`
6. Use `language.direction` to set content direction

## Error Expectations (Read Endpoints)

- `404` if language/chapter not found
- `401/403` generally for write endpoints
- Read endpoints are usable without auth, but may return reduced layer set (active-only)
