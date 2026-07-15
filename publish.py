""" Publishing and rendering script for Quarto website.

This script provides a platform-independent Python code for automatic
project synchronization, incremental compilation of Quarto files, and
deployment to GitHub Pages.
"""

import argparse
import os
import subprocess
import sys
import frontmatter
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
""" Path to the parent directory of this script. """


def sync_project() -> None:
    """ Ensure the project dependencies are in sync using uv. """
    print("Syncing project dependencies...")
    subprocess.run(["uv", "sync"], cwd=SCRIPT_DIR, check=True)


def setup_environment() -> None:
    """ Set up environment variables for the rendering process. """
    # Find local virtual environment Python
    venv_python = SCRIPT_DIR / ".venv" / "Scripts" / "python.exe"

    if not venv_python.exists():
        # Fallback to Unix path
        venv_python = SCRIPT_DIR / ".venv" / "bin" / "python"

    os.environ["QUARTO_PYTHON"] = str(venv_python)


def get_expected_outputs(qmd_path: Path) -> list[str]:
    """ Parse the YAML of a .qmd file to find expected outputs.

    Parameters
    ----------
    qmd_path : Path
        The path to the .qmd file.

    Returns
    -------
    list[str]
        A list of expected output filenames (e.g. ['index.html']).
    """
    try:
        post = frontmatter.load(qmd_path)
        fmt_data = post.metadata.get("format")
    except Exception:
        return [qmd_path.stem + ".html"]

    formats: list[str] = []

    if isinstance(fmt_data, dict):
        formats = list(fmt_data.keys())
    elif isinstance(fmt_data, list):
        formats = [str(f) for f in fmt_data]
    elif isinstance(fmt_data, str) and fmt_data.strip():
        formats = [fmt_data.strip()]

    if not formats:
        formats = ["html"]

    base_name = qmd_path.stem
    outputs: list[str] = []

    for fmt in formats:
        fmt_lower = fmt.lower()
        if "html" in fmt_lower or "revealjs" in fmt_lower:
            ext = ".html"
        elif (
            "pdf" in fmt_lower
            or "typst" in fmt_lower
            or "beamer" in fmt_lower
        ):
            ext = ".pdf"
        elif "docx" in fmt_lower or "msword" in fmt_lower:
            ext = ".docx"
        elif "epub" in fmt_lower:
            ext = ".epub"
        elif "odt" in fmt_lower:
            ext = ".odt"
        else:
            ext = f".{fmt_lower}"

        out_file = base_name + ext

        if out_file not in outputs:
            outputs.append(out_file)

    return outputs


def find_qmd_files(root_dir: Path) -> list[Path]:
    """ Find all .qmd files in the repository, excluding dot directories.

    Parameters
    ----------
    root_dir : Path
        The root directory to search.

    Returns
    -------
    list[Path]
        A list of Paths to .qmd files.
    """
    qmd_files: list[Path] = []

    def traverse(path: Path) -> None:
        for child in path.iterdir():
            if child.name.startswith("."):
                continue
            if child.is_dir():
                traverse(child)
            elif child.suffix == ".qmd":
                qmd_files.append(child)

    traverse(root_dir)
    return qmd_files


def render_qmd(qmd_path: Path, target_dir: Path) -> None:
    """ Render a .qmd file to the target directory using Quarto.

    Parameters
    ----------
    qmd_path : Path
        The path to the .qmd file.
    target_dir : Path
        The output directory.
    """
    print(f"Rendering {qmd_path} to \n - {target_dir}\n")
    subprocess.run(
        [
            "quarto",
            "render",
            str(qmd_path),
            "--output-dir",
            str(target_dir),
            "--no-clean",
        ],
        check=True,
    )


def render_site() -> None:
    """ Manages rendering all files in the directory. """
    # Ensure _site directory exists
    site_dir = SCRIPT_DIR / "_site"
    site_dir.mkdir(exist_ok=True)

    qmd_files = find_qmd_files(SCRIPT_DIR)

    for qmd_path in qmd_files:
        relative_dir = qmd_path.parent.relative_to(SCRIPT_DIR)
        target_dir = site_dir / relative_dir

        expected_outputs = get_expected_outputs(qmd_path)
        should_render = False

        for out_file in expected_outputs:
            out_path = target_dir / out_file
            if not out_path.exists():
                should_render = True
                break
            if qmd_path.stat().st_mtime > out_path.stat().st_mtime:
                should_render = True
                break

        if should_render:
            render_qmd(qmd_path, target_dir)
        else:
            print(f"Skipping {qmd_path.name} (up to date)")


def publish_site() -> None:
    """ Deploy the compiled website files in _site to gh-pages branch. """
    site_dir = SCRIPT_DIR / "_site"
    if not site_dir.exists():
        print(f"Error: {site_dir} does not exist. Run render first.")
        sys.exit(1)

    # Get origin URL from parent repo
    res = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        cwd=SCRIPT_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    origin_url = res.stdout.strip()

    # Re-initialize git in _site
    subprocess.run(
        ["git", "config", "--global", "init.defaultBranch", "main"],
        check=True,
    )
    subprocess.run(["git", "init"], cwd=site_dir, check=True)

    # Create .nojekyll
    nojekyll_path = site_dir / ".nojekyll"
    nojekyll_path.touch(exist_ok=True)

    # Manage origin remote
    try:
        subprocess.run(
            ["git", "remote", "remove", "origin"],
            cwd=site_dir,
            capture_output=True,
        )
    except Exception:
        pass

    subprocess.run(
        ["git", "remote", "add", "origin", origin_url],
        cwd=site_dir,
        check=True,
    )

    # Stage all changes
    subprocess.run(["git", "add", "-A"], cwd=site_dir, check=True)

    # Check if there are changes to commit
    status_res = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=site_dir,
        capture_output=True,
        text=True,
        check=True,
    )
    if not status_res.stdout.strip():
        print("No changes to commit. gh-pages is up to date.")
        return

    # Commit
    subprocess.run(
        ["git", "commit", "-m", "Deploy independent docs manually"],
        cwd=site_dir,
        check=True,
    )

    # Push force
    subprocess.run(
        ["git", "push", "origin", "HEAD:gh-pages", "--force"],
        cwd=site_dir,
        check=True,
    )


def main() -> None:
    """ Main entry point for the publish script. """
    parser = argparse.ArgumentParser(
        description="Render and publish Quarto project."
    )
    parser.add_argument(
        "-r",
        "--render",
        action="store_true",
        help="Render all modified .qmd files.",
    )
    parser.add_argument(
        "-p",
        "--publish",
        action="store_true",
        help="Publish site to GitHub Pages.",
    )

    args = parser.parse_args()

    # If no flags are provided, show help and exit
    if not args.render and not args.publish:
        parser.print_help()
        sys.exit(1)

    # Make sure the project is in sync
    sync_project()

    # Setup the QUARTO_PYTHON environment variable
    setup_environment()

    if args.render:
        render_site()

    if args.publish:
        publish_site()


if __name__ == "__main__":
    main()
