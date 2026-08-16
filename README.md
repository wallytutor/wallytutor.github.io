# wallytutor.github.io

1. Rendering locally the documents:

```bash
quarto render index.qmd
```

2. Publishing to GitHub pages:

```bash
# First render everything and inspect:
uv run python publish.py --render

# Then publish to the right branch:
uv run python publish.py --publish
```

3. Troubleshooting:

```bash
$env:QUARTO_PYTHON = ".venv/Scripts/python.exe"

quarto render 'some-file.qmd'
```