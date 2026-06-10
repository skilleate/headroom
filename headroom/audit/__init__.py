"""Offline traffic audits — measure opportunity sizes before tuning defaults."""

from .reads import ReadAuditReport, audit_reads, render_text

__all__ = ["ReadAuditReport", "audit_reads", "render_text"]
