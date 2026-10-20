# Theming

The news in your app (the button, the panel, `<tayori-news>`) and the
public page take their look from `tayori.css`. Every colour, space, radius
and font is a `--tayori-*` custom property: set them on `.tayori-panel`,
`.tayori-button` or higher.

```css
@import "../../deps/tayori/priv/static/tayori.css";

:root {
  --tayori-accent: #0f766e;
  --tayori-radius: 4px;
}
```

The defaults have no specificity, so a value set anywhere wins. They are
the defaults of Kotoba, Koyomi and Jumon, so that a page with them all
looks like one thing. The body of each entry is Kotoba content: Tayori
gives it the news's colours, and `kotoba.css` styles it.

## The properties

### Type

| Property | Default | Use |
| --- | --- | --- |
| `--tayori-font` | the system's | the text |
| `--tayori-title-font` | `--tayori-font` | the titles |
| `--tayori-mono` | the system's | code |
| `--tayori-font-size` | `1rem` | the text |
| `--tayori-small` | `0.875rem` | dates, categories |
| `--tayori-tiny` | `0.75rem` | the smallest |
| `--tayori-line-height` | `1.6` | |
| `--tayori-weight` | `400` | the text |
| `--tayori-title-weight` | `600` | the titles |
| `--tayori-title-tracking` | `-0.015em` | the titles |
| `--tayori-title-line-height` | `1.25` | the titles |

### Colours

| Property | Default | Use |
| --- | --- | --- |
| `--tayori-text` | `#1f1f23` | the text |
| `--tayori-muted` | `#6b6b76` | dates, hints |
| `--tayori-background` | `#ffffff` | the panel, the page |
| `--tayori-surface` | `#f6f6f7` | categories, hovers |
| `--tayori-canvas` | `#f6f6f7` | behind the cards |
| `--tayori-border` | `#d9d9de` | lines |
| `--tayori-rule` | `#ececef` | the rules between entries |
| `--tayori-accent` | `#2f5bd3` | links, buttons |
| `--tayori-accent-text` | `#ffffff` | text on the accent |
| `--tayori-attention`, `--tayori-attention-text` | the accent | the count on the button, the New mark |
| `--tayori-danger`, `--tayori-success` | | errors, confirmations |
| `--tayori-gray`, `--tayori-red`, `--tayori-orange`, `--tayori-amber`, `--tayori-green`, `--tayori-teal`, `--tayori-blue`, `--tayori-purple`, `--tayori-pink` | | the colours of the categories |

### Shape and space

| Property | Default | Use |
| --- | --- | --- |
| `--tayori-radius` | `6px` | buttons, inputs |
| `--tayori-radius-inner` | `4px` | small things |
| `--tayori-radius-card` | `10px` | cards |
| `--tayori-radius-panel` | `12px` | the panel |
| `--tayori-radius-media` | `8px` | covers, images |
| `--tayori-space` | `0.5rem` | |
| `--tayori-icon-size` | `18px` | the icons |
| `--tayori-panel-width` | `27rem` | |
| `--tayori-page-width` | `46rem` | the column of the public page |
| `--tayori-shadow`, `--tayori-shadow-card`, `--tayori-shadow-panel` | | |
| `--tayori-focus-ring` | | the focus |

## Dark mode

The defaults are light, and dark under `data-theme="dark"` (the attribute
of Phoenix's themes) or the class `dark`. To follow the system instead:

```css
@media (prefers-color-scheme: dark) {
  :root {
    --tayori-text: #ececf1;
    --tayori-background: #1b1b1f;
    /* ... */
  }
}
```

## The Sumi theme

Sumi is the design system of Hattori AI, the makers of Tayori, Kotoba,
Koyomi and Jumon. Import it after `tayori.css`:

```css
@import "../../deps/tayori/priv/static/tayori.css";
@import "../../deps/tayori/priv/static/tayori-sumi.css";
```

It gives every property a Sumi value, from the Sumi tokens of your page
(`--font-body`, `--color-sumi-blade`, the Sumi daisyUI themes), else from
short `--sumi-*` names your page sets, else from its own palette: paper
and ink, Outfit for the text and Cormorant Garamond for the titles, and
the blade for what needs attention (the count, the New mark). It follows
`data-theme`, then `prefers-color-scheme`. It loads no fonts.

## The admin

The admin has its own styles, in Tayori's theme or Sumi's
(`tayori_admin "/news", theme: :sumi`); your CSS does not reach it.

## Classes

The classes are stable: `.tayori-button`, `.tayori-badge`,
`.tayori-panel`, `.tayori-panel-header`, `.tayori-panel-body`,
`.tayori-news`, `.tayori-entry`, `.tayori-entry-meta`, `.tayori-new`,
`.tayori-category`, `.tayori-entry-title`, `.tayori-entry-body`,
`.tayori-more`, and on the public page `.tayori-page`.

## Forced colours and motion

In forced colours, the badge, the New mark and the panel have borders.
With reduced motion, the panel appears without its slide.
