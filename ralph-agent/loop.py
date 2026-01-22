#!/usr/bin/env python3
"""
Ralph-Agent Loop Controller

External loop for long-running agent execution.
Spawns Claude Code with plugin agents, commits between iterations.

Usage:
    ./loop.py ralph                 # Ralph unlimited
    ./loop.py ralph 10              # Ralph max 10 iterations
    ./loop.py gbuild 50             # Geoff Builder max 50
    ./loop.py gplan                 # Geoff Planner (one-shot, not looped)

    # With custom parallelism
    ./loop.py gbuild 100 --parallel 200

    # With custom plugin path
    ./loop.py ralph 20 --plugin-dir /path/to/ralph-agent
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Optional


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Ralph-Agent Loop Controller",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s ralph 10              # Run Ralph for 10 iterations
  %(prog)s gbuild 0              # Run Geoff Builder unlimited
  %(prog)s gbuild 50 --parallel 100  # With custom parallelism
  %(prog)s ralph 5 --plugin-dir /custom/path
        """
    )

    parser.add_argument(
        "agent",
        choices=["ralph", "gbuild", "gplan"],
        help="Agent to run (ralph, gbuild, gplan)"
    )

    parser.add_argument(
        "max_iterations",
        type=int,
        nargs="?",
        default=0,
        help="Maximum iterations (0 = unlimited, default: 0)"
    )

    parser.add_argument(
        "--parallel", "-p",
        type=int,
        default=10,
        help="Parallel subagents (for gbuild/gplan, default: 10)"
    )

    parser.add_argument(
        "--plugin-dir", "-d",
        type=str,
        default=None,
        help="Path to ralph-agent plugin (default: ./ralph-agent)"
    )

    parser.add_argument(
        "--model", "-m",
        type=str,
        default="opus",
        choices=["opus", "sonnet", "haiku"],
        help="Claude model to use (default: opus)"
    )

    parser.add_argument(
        "--skip-push",
        action="store_true",
        help="Skip git push (commit only)"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show commands without executing"
    )

    return parser.parse_args()


def get_plugin_path(args: argparse.Namespace) -> Path:
    """Get the plugin directory path."""
    if args.plugin_dir:
        return Path(args.plugin_dir)

    # Auto-detect: try common locations
    script_dir = Path(__file__).parent
    candidates = [
        script_dir,                    # ralph-agent/
        script_dir / ".claude-plugin", # ralph-agent/.claude-plugin/
        Path.cwd() / "ralph-agent",    # ./ralph-agent/
        Path.cwd() / ".claude-plugin", # ./.claude-plugin/
    ]

    for candidate in candidates:
        if candidate.exists() and (candidate / "plugin.json").exists():
            print(f"Auto-detected plugin at: {candidate}")
            return candidate

    # Default to script directory
    return script_dir


def verify_plugin(plugin_path: Path) -> bool:
    """Verify that the plugin exists and is valid."""
    plugin_json = plugin_path / "plugin.json"

    if not plugin_json.exists():
        print(f"Error: plugin.json not found at {plugin_path}", file=sys.stderr)
        return False

    try:
        with open(plugin_json) as f:
            data = json.load(f)
            print(f"Plugin: {data.get('name', 'unknown')} v{data.get('version', 'unknown')}")
            print(f"Agents: {', '.join(data.get('agents', []))}")
            print(f"Commands: {', '.join(data.get('commands', []))}")
    except Exception as e:
        print(f"Warning: Could not read plugin.json: {e}")

    return True


def get_git_branch() -> str:
    """Get current git branch name."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return "unknown"


def get_git_tags() -> list:
    """Get list of git tags."""
    try:
        result = subprocess.run(
            ["git", "tag", "--list"],
            capture_output=True,
            text=True,
            check=True
        )
        return [t.strip() for t in result.stdout.splitlines() if t.strip()]
    except subprocess.CalledProcessError:
        return []


def display_banner(args: argparse.Namespace, plugin_path: Path) -> None:
    """Display configuration banner."""
    branch = get_git_branch()
    tags = get_git_tags()
    iterations_str = "unlimited" if args.max_iterations == 0 else str(args.max_iterations)

    print("\n" + "=" * 80)
    print("RALPH-AGENT LOOP CONTROLLER")
    print("=" * 80)
    print(f"Agent:             {args.agent}")
    print(f"Max iterations:    {iterations_str}")
    print(f"Parallel agents:   {args.parallel}")
    print(f"Plugin path:       {plugin_path}")
    print(f"Model:             {args.model}")
    print(f"Git branch:        {branch}")
    if tags:
        print(f"Current tags:      {', '.join(tags[-5:])}")  # Last 5 tags
    print("=" * 80 + "\n")


def build_claude_command(
    args: argparse.Namespace,
    plugin_path: Path,
    iteration: int
) -> list:
    """Build Claude command for the agent.

    Uses --agents CLI flag (priority 1 - highest) for agent definition.
    """

    # Load agent definition from plugin
    agent_file = plugin_path / "agents" / f"{args.agent}.md"

    if not agent_file.exists():
        print(f"Error: Agent file not found: {agent_file}", file=sys.stderr)
        sys.exit(1)

    # Build --agents JSON (priority 1 - highest priority)
    agents_json = {
        args.agent: {
            "description": f"Loaded from ralph-agent plugin via loop.py",
            "prompt": f"See agent definition at {agent_file}",
            "tools": ["Task", "Read", "Write", "Edit", "Grep", "Glob", "Bash"],
            "model": args.model
        }
    }

    cmd = [
        "claude",
        "--agents", json.dumps(agents_json),
        "--plugin-dir", str(plugin_path),  # Also load plugin for commands
        "--model", args.model,
    ]

    # Add agent command (invokes the agent)
    if args.agent == "ralph":
        cmd.extend(["/ralph", f"--max-iterations={args.max_iterations}"])
    elif args.agent == "gbuild":
        cmd.extend(["/gbuild", f"--parallel={args.parallel}"])
        if args.max_iterations > 0:
            cmd.append(f"--max-iterations={args.max_iterations}")
    elif args.agent == "gplan":
        cmd.extend(["/gplan", f"--parallel={args.parallel}"])

    return cmd


def run_agent_iteration(
    args: argparse.Namespace,
    plugin_path: Path,
    iteration: int
) -> bool:
    """
    Run one iteration of the agent.

    Args:
        args: Parsed arguments
        plugin_path: Path to plugin directory
        iteration: Current iteration number

    Returns:
        True if successful, False otherwise
    """
    cmd = build_claude_command(args, plugin_path, iteration)

    print(f"\n{'─' * 80}")
    print(f"ITERATION {iteration}" + (f"/{args.max_iterations}" if args.max_iterations > 0 else ""))
    print(f"{'─' * 80}\n")

    print(f"Command: {' '.join(cmd)}\n")

    if args.dry_run:
        print("[DRY RUN] Would execute the command above.")
        return True

    try:
        result = subprocess.run(cmd, check=False)
        success = result.returncode == 0

        if not success:
            print(f"Warning: Agent exited with code {result.returncode}")

        return success

    except FileNotFoundError:
        print("Error: 'claude' command not found", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Error running agent: {e}", file=sys.stderr)
        return False


def git_commit(iteration: int, agent: str) -> bool:
    """
    Stage and commit changes.

    Args:
        iteration: Iteration number
        agent: Agent name

    Returns:
        True if successful, False otherwise
    """
    try:
        # Stage all changes
        subprocess.run(["git", "add", "-A"], check=True, capture_output=True)

        # Check if there's anything to commit
        result = subprocess.run(
            ["git", "diff", "--cached", "--quiet"],
            check=False
        )

        # Nothing to commit (diff returns 0 if no changes, 1 if changes)
        if result.returncode == 0:
            print("  No changes to commit.")
            return True

        # Commit with descriptive message
        commit_msg = f"[{agent.upper()}] Iteration {iteration}"

        result = subprocess.run(
            ["git", "commit", "-m", commit_msg],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode == 0:
            print(f"  ✓ Committed: {commit_msg}")
            return True
        else:
            print(f"  Warning: Commit failed")
            return False

    except Exception as e:
        print(f"  Error during git commit: {e}", file=sys.stderr)
        return False


def git_tag(iteration: int, agent: str) -> bool:
    """
    Create git tag for gbuild iterations.

    Args:
        iteration: Iteration number
        agent: Agent name

    Returns:
        True if successful, False otherwise
    """
    if agent != "gbuild":
        return True

    try:
        # Get existing tags
        tags = get_git_tags()

        # Determine next version
        if tags:
            # Parse last tag and increment patch
            try:
                last_tag = tags[-1]
                parts = last_tag.split(".")
                if len(parts) == 3 and all(p.isdigit() for p in parts):
                    major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])
                    patch += 1
                    new_tag = f"{major}.{minor}.{patch}"
                else:
                    new_tag = f"0.0.{iteration}"
            except:
                new_tag = f"0.0.{iteration}"
        else:
            new_tag = "0.0.0"

        # Create annotated tag
        tag_msg = f"{agent.upper()} iteration {iteration}"
        result = subprocess.run(
            ["git", "tag", "-a", new_tag, "-m", tag_msg],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode == 0:
            print(f"  ✓ Tagged: {new_tag}")
            return True
        else:
            print(f"  Warning: Tag creation failed")
            return False

    except Exception as e:
        print(f"  Error during git tag: {e}", file=sys.stderr)
        return False


def git_push(skip: bool) -> bool:
    """
    Push changes and tags to remote.

    Args:
        skip: If True, skip pushing

    Returns:
        True if successful, False otherwise
    """
    if skip:
        print("  ⊘ Push skipped (--skip-push)")
        return True

    try:
        # Push commits
        result = subprocess.run(
            ["git", "push"],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode != 0:
            # Try setting upstream
            branch = get_git_branch()
            result = subprocess.run(
                ["git", "push", "--set-upstream", "origin", branch],
                capture_output=True,
                text=True,
                check=False
            )

        if result.returncode == 0:
            # Push tags
            subprocess.run(
                ["git", "push", "--tags"],
                capture_output=True,
                check=False
            )
            print("  ✓ Pushed to remote")
            return True
        else:
            print(f"  Warning: Push failed - {result.stderr.strip()}")
            return False

    except Exception as e:
        print(f"  Error during git push: {e}", file=sys.stderr)
        return False


def run_loop(args: argparse.Namespace, plugin_path: Path) -> None:
    """
    Run the main loop.

    Args:
        args: Parsed arguments
        plugin_path: Path to plugin directory
    """
    iteration = 1

    try:
        while True:
            # Check max iterations
            if args.max_iterations > 0 and iteration > args.max_iterations:
                print(f"\n{'=' * 80}")
                print(f"MAX ITERATIONS REACHED ({args.max_iterations})")
                print(f"{'=' * 80}\n")
                break

            # Run agent
            if not run_agent_iteration(args, plugin_path, iteration):
                print(f"\nAgent failed at iteration {iteration}. Stopping.")
                break

            # Git workflow
            print(f"\nGit workflow...")
            git_commit(iteration, args.agent)
            git_tag(iteration, args.agent)
            git_push(args.skip_push)

            iteration += 1

            # For gplan, stop after first iteration (planning is one-shot)
            if args.agent == "gplan":
                print("\nPlanning complete (gplan is one-shot).")
                break

    except KeyboardInterrupt:
        print(f"\n\n{'=' * 80}")
        print(f"INTERRUPTED by user at iteration {iteration}")
        print(f"{'=' * 80}\n")
        sys.exit(0)


def main() -> None:
    """Main entry point."""
    args = parse_arguments()
    plugin_path = get_plugin_path(args)

    if not verify_plugin(plugin_path):
        sys.exit(1)

    display_banner(args, plugin_path)

    if args.dry_run:
        print("[DRY RUN MODE] - Commands will be shown but not executed.\n")

    run_loop(args, plugin_path)


if __name__ == "__main__":
    main()
