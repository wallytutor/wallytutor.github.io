param (
    [switch]$Render,
    [switch]$Publish
)

# Make sure the project is in sync:
uv sync

# Make sure the right Python is used:
$env:QUARTO_PYTHON = "$PSScriptRoot\.venv\Scripts\python.exe"

if ($Render) {
    # Make sure that all previous files are cleaned:
    Remove-Item -Recurse -Force _site -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path _site | Out-Null

    # Build all .qmd files (Quarto will gather the assets as needed):
    Get-ChildItem -Filter *.qmd -Recurse `
    | Where-Object { $_.FullName -notlike "*\.*" } | ForEach-Object {
        # XXX do not use the following, as it will fail for the root!
        # $relativeDir = $_.DirectoryName | Split-Path -Leaf
        $relativeDir = $_.DirectoryName.Substring($PSScriptRoot.Length).TrimStart('\')
        $targetDir = Join-Path "$PSScriptRoot\_site" $relativeDir

        Write-Host "Rendering $($_.FullName) to `n - $targetDir`n"
        quarto render $_.FullName --output-dir "$targetDir"
    }
}

if ($Publish) {
    # Force push the folder to your gh-pages branch
    cd "$PSScriptRoot\_site"
    git config --global init.defaultBranch main
    git init

    # Create .nojekyll file to prevent GitHub Pages from ignoring
    # directories starting with underscore (like _assets)
    New-Item -ItemType File -Path ".nojekyll" -Force | Out-Null

    git add -A
    git commit -m "Deploy independent docs manually"
    git remote add origin (git -C "$PSScriptRoot" remote get-url origin)
    git push origin HEAD:gh-pages --force

    cd $PSScriptRoot
    Remove-Item -Recurse -Force _site
}
