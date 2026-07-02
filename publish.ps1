param (
    [switch]$Render,
    [switch]$Publish
)

if ($Render) {
    # Make sure that all previous files are cleaned:
    Remove-Item -Recurse -Force _site -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path _site | Out-Null

    Get-ChildItem -Filter *.qmd -Recurse `
    | Where-Object { $_.FullName -notlike "*\.*" } | ForEach-Object {
        $relativeDir = $_.DirectoryName.Substring($PSScriptRoot.Length).TrimStart('\')
        $targetDir = Join-Path "$PSScriptRoot\_site" $relativeDir

        Write-Host "Rendering $($_.FullName) to `n - $targetDir`n"
        quarto render $_.FullName --output-dir "$targetDir"
    }

    Copy-Item -Recurse -Force "_assets" "$PSScriptRoot\_site"
}

if ($Publish) {
    # Force push the folder to your gh-pages branch
    cd "$PSScriptRoot\_site"
    git init
    git add -A
    git commit -m "Deploy independent docs manually"
    git remote add origin (git -C "$PSScriptRoot" remote get-url origin)
    git push origin HEAD:gh-pages --force
    cd $PSScriptRoot
}

Remove-Item -Recurse -Force _site