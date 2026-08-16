# wallytutor.github.io

1. Rendering locally the documents:

```bash
uv run majordome-build-qmd --file shorts/scientific-computing.qmd
```

2. Publishing to GitHub pages:

```bash
# First render everything and inspect:
uv run python publish.py --render

# Then publish to the right branch:
uv run python publish.py --publish
```
