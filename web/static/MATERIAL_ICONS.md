# Material Icons Font - Download Instructions

The `material-icons.woff2` file is required for the web console to display icons properly.

## Automatic Installation

The `install.sh` script will automatically download this file during installation.

## Manual Download

If you need to download it manually:

```bash
cd web/static
curl -o material-icons.woff2 'https://fonts.gstatic.com/s/materialicons/v140/flUhRq6tzZclQEJ-Vdg-IuiaDsNc.woff2'
```

**File Details:**
- Name: `material-icons.woff2`
- Size: ~126 KB
- Format: WOFF2 (Web Open Font Format 2)
- License: Apache License 2.0
- Source: Google Fonts

## Verification

After downloading, verify the file:

```bash
ls -lh material-icons.woff2
# Should show: ~126K file size
```

## Usage

The font is referenced in `style.css`:

```css
@font-face {
    font-family: 'Material Icons';
    font-style: normal;
    font-weight: 400;
    src: url('material-icons.woff2') format('woff2');
}
```

## Why Not Included in Git?

The font file is a binary file (~126KB) and is typically not committed to Git repositories. Instead, it's downloaded during installation to:
- Keep repository size small
- Ensure latest version is used
- Comply with Git best practices

## Alternative: CDN Version

If you prefer using a CDN instead of hosting locally, modify `style.css`:

```css
@import url('https://fonts.googleapis.com/icon?family=Material+Icons');
```

However, this requires internet connectivity, while the local version works offline.

## License

Material Icons are licensed under the Apache License 2.0.
See: https://github.com/google/material-design-icons/blob/master/LICENSE
