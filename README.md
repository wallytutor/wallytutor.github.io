# wallytutor.github.io

1. Rendering locally the documents:

```bash
quarto render index.qmd
```

2. Publishing to GitHub pages:

```bash
quarto publish gh-pages --no-prompt --no-browser index.qmd
```

3. Troubleshooting:

```bash
$env:QUARTO_PYTHON = ".venv/Scripts/python.exe"

quarto render 'some-file.qmd'
```