"""Traffic audit CLI commands."""

from pathlib import Path

import click

from .main import main


@main.command(name="audit-reads")
@click.option(
    "--path",
    "root",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    default=None,
    help="Transcript directory to audit (default: ~/.claude/projects)",
)
@click.option(
    "--format",
    "output_format",
    type=click.Choice(["text", "json"]),
    default="text",
    help="Output format (default: text)",
)
def audit_reads_cmd(root: Path | None, output_format: str) -> None:
    """Audit Read-tool traffic for compression opportunities.

    Streams local Claude Code transcripts (read-only) and sizes the
    addressable bytes for each Read mechanism: identical repeats, subset
    containment, write-readback, stale reads, line-number scaffolding,
    context residency, and cache-death windows.

    \b
    Run this on a deployment's transcripts BEFORE tuning compression
    defaults — opportunity sizes vary heavily by workload.

    \b
    Examples:
        headroom audit-reads
        headroom audit-reads --path /var/transcripts --format json
    """
    from headroom.audit.reads import audit_reads, render_text

    if root is None:
        root = Path.home() / ".claude" / "projects"
        if not root.exists():
            raise click.ClickException(
                f"{root} does not exist — pass --path to the transcript directory"
            )

    report = audit_reads(root)
    if report.sessions == 0:
        raise click.ClickException(f"no *.jsonl transcripts found under {root}")

    if output_format == "json":
        click.echo(report.to_json())
    else:
        click.echo(render_text(report))
