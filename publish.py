""" Publishing and rendering script for Quarto website.

This script provides a platform-independent Python code for automatic
project synchronization, incremental compilation of Quarto files, and
deployment to GitHub Pages.
"""

import argparse
import os
import subprocess
import sys
from typing import List


def sync_project(script_dir: str) -> None:
    """ Ensure the project dependencies are in sync using uv.

    Parameters
    ----------
    script_dir : str
        The directory of the script.
    """
    print("Syncing project dependencies...")
    subprocess.run(["uv", "sync"], cwd=script_dir, check=True)


def setup_environment(script_dir: str) -> None:
    """ Set up environment variables for the rendering process.

    Parameters
    ----------
    script_dir : str
        The directory of the script.
    """
    # Find local virtual environment Python
    venv_python = os.path.join(
        script_dir, ".venv", "Scripts", "python.exe"
    )
    if not os.path.exists(venv_python):
        # Fallback to Unix path
        venv_python = os.path.join(script_dir, ".venv", "bin", "python")

    os.environ["QUARTO_PYTHON"] = venv_python


def get_expected_outputs(qmd_path: str) -> List[str]:
    """ Parse the YAML of a .qmd file to find expected outputs.

    Parameters
    ----------
    qmd_path : str
        The path to the .qmd file.

    Returns
    -------
    List[str]
        A list of expected output filenames (e.g. ['index.html']).
    """
    formats: List[str] = []
    try:
        with open(qmd_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        # Default to html on read failure
        base_name = os.path.splitext(os.path.basename(qmd_path))[0]
        return [base_name + ".html"]

    front_matter: List[str] = []
    in_front_matter = False
    for line in lines:
        stripped = line.strip()
        if stripped == "---":
            if not in_front_matter:
                in_front_matter = True
                continue
            else:
                break
        if in_front_matter:
            front_matter.append(line)

    format_index = -1
    format_indent = -1
    for i, line in enumerate(front_matter):
        stripped = line.strip()
        if stripped.startswith("format:") or (
            ":" in stripped
            and stripped.split(":", 1)[0].strip() == "format"
        ):
            format_index = i
            format_indent = len(line) - len(line.lstrip())
            break

    if format_index != -1:
        parts = front_matter[format_index].split(":", 1)
        value = parts[1].strip() if len(parts) > 1 else ""
        if "#" in value:
            value = value.split("#", 1)[0].strip()

        if value:
            if value.startswith("[") and value.endswith("]"):
                formats = [
                    fmt.strip().strip('"').strip("'")
                    for fmt in value[1:-1].split(",")
                ]
            else:
                formats = [value.strip('"').strip("'")]
        else:
            sub_indent = -1
            for j in range(format_index + 1, len(front_matter)):
                line = front_matter[j]
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                indent = len(line) - len(line.lstrip())
                if indent <= format_indent:
                    break
                if sub_indent == -1:
                    sub_indent = indent
                if indent == sub_indent:
                    if ":" in stripped:
                        key = (
                            stripped.split(":", 1)[0]
                            .strip()
                            .strip('"')
                            .strip("'")
                        )
                        formats.append(key)

    if not formats:
        formats = ["html"]

    base_name = os.path.splitext(os.path.basename(qmd_path))[0]
    outputs: List[str] = []
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


def find_qmd_files(root_dir: str) -> List[str]:
    """ Find all .qmd files in the repository, excluding dot directories.

    Parameters
    ----------
    root_dir : str
        The root directory to search.

    Returns
    -------
    List[str]
        A list of absolute paths to .qmd files.
    """
    qmd_files: List[str] = []
    for root, dirs, files in os.walk(root_dir):
        # Modify dirs in-place to ignore dot directories
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for file in files:
            if file.endswith(".qmd") and not file.startswith("."):
                qmd_files.append(os.path.join(root, file))
    return qmd_files


def render_qmd(qmd_path: str, target_dir: str) -> None:
    """ Render a .qmd file to the target directory using Quarto.

    Parameters
    ----------
    qmd_path : str
        The path to the .qmd file.
    target_dir : str
        The output directory.
    """
    print(f"Rendering {qmd_path} to \n - {target_dir}\n")
    subprocess.run(
        [
            "quarto",
            "render",
            qmd_path,
            "--output-dir",
            target_dir,
            "--no-clean",
        ],
        check=True,
    )


def publish_site(script_dir: str) -> None:
    """ Deploy the compiled website files in _site to gh-pages branch.

    Parameters
    ----------
    script_dir : str
        The directory of the script.
    """
    site_dir = os.path.join(script_dir, "_site")
    if not os.path.exists(site_dir):
        print(f"Error: {site_dir} does not exist. Run render first.")
        sys.exit(1)

    # Get origin URL from parent repo
    res = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        cwd=script_dir,
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
    nojekyll_path = os.path.join(site_dir, ".nojekyll")
    with open(nojekyll_path, "w", encoding="utf-8") as f:
        pass

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
    """
    Main entry point for the publish script.

    Parses arguments, sets up the environment, and performs render
    and/or publish operations.
    """
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

    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Make sure the project is in sync
    sync_project(script_dir)

    # Setup the QUARTO_PYTHON environment variable
    setup_environment(script_dir)

    if args.render:
        # Ensure _site directory exists
        site_dir = os.path.join(script_dir, "_site")
        os.makedirs(site_dir, exist_ok=True)

        qmd_files = find_qmd_files(script_dir)
        for qmd_path in qmd_files:
            relative_dir = os.path.relpath(
                os.path.dirname(qmd_path), script_dir
            )
            if relative_dir == ".":
                relative_dir = ""
            target_dir = os.path.join(site_dir, relative_dir)

            expected_outputs = get_expected_outputs(qmd_path)
            should_render = False

            for out_file in expected_outputs:
                out_path = os.path.join(target_dir, out_file)
                if not os.path.exists(out_path):
                    should_render = True
                    break
                if os.path.getmtime(qmd_path) > os.path.getmtime(out_path):
                    should_render = True
                    break

            if should_render:
                render_qmd(qmd_path, target_dir)
            else:
                print(
                    f"Skipping {os.path.basename(qmd_path)} "
                    "(up to date)"
                )

    if args.publish:
        publish_site(script_dir)


if __name__ == "__main__":
    main()
