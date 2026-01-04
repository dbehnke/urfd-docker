# Description

This PR adds comprehensive system documentation for URFD, including a high-level overview, architecture diagrams, and internal details.

## Changes

- Added `docs/SYSTEM_OVERVIEW.md`: Main documentation file.
- Added `docs/SYSTEM_OVERVIEW.pdf`: Generated PDF version with embedded diagrams.
- Added 5 Mermaid diagrams (`docs/diagrams/*.mmd`) covering Motivation, Architecture, Internals, Transcoding, and Pipeline.
- Fixed Mermaid syntax compatibility issues between GitHub and PDF generation.
- Embedded pre-rendered high-quality PNGs in the PDF to ensure correct rendering.

## Review Notes

### Documentation Rendering

- Verified that `SYSTEM_OVERVIEW.md` renders correctly on GitHub (using standard CommonMark list handling).
- Confirmed that `SYSTEM_OVERVIEW.pdf` contains all images and proper page breaks (specifically isolating the Transcoding section).

### Technical Details

- **Mermaid Fixes**: Switched from "Note" syntax in Flowcharts (which is invalid/unsupported in some renderers) to standard Nodes for compatibility.
- **Image Handling**: All diagrams are exported as PNGs and stored in `docs/images/` to support the PDF generation pipeline without relying on external services at runtime.

### Verification

- [x] GitHub Rendering: Checked
- [x] PDF Content: Checked
