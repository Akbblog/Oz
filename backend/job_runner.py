"""
Durable job runner.

The API process (``JOB_RUNNER_MODE=inprocess``, the default) or a dedicated
worker process (``python job_worker.py`` with the API set to
``JOB_RUNNER_MODE=external``) runs this loop:

1. requeue ``running`` jobs whose heartbeat went stale (crashed / restarted
   worker) so they resume from ``completed_cities``;
2. settle credits for terminal jobs nobody settled;
3. claim ``pending`` jobs up to ``JOB_WORKER_CONCURRENCY`` and run them.

Claiming is an atomic conditional UPDATE, so several workers (or API replicas)
can share one database without running the same job twice.
"""

from __future__ import annotations

import asyncio
import logging
import os
import socket
import time
import uuid
from typing import Awaitable, Callable, Dict, Optional

import job_service

logger = logging.getLogger(__name__)

RunFn = Callable[[str, str], Awaitable[None]]  # (job_id, worker_id)


def runner_mode() -> str:
    mode = os.getenv("JOB_RUNNER_MODE", "inprocess").strip().lower()
    return mode if mode in ("inprocess", "external", "off") else "inprocess"


def _int_env(name: str, default: int, minimum: int = 1) -> int:
    try:
        return max(minimum, int(os.getenv(name, str(default))))
    except ValueError:
        return default


class JobRunner:
    def __init__(self, run_fn: RunFn, *, concurrency: Optional[int] = None,
                 poll_seconds: Optional[float] = None, worker_id: Optional[str] = None):
        self._run_fn = run_fn
        self.concurrency = concurrency or _int_env("JOB_WORKER_CONCURRENCY", 2)
        self.poll_seconds = poll_seconds or float(_int_env("JOB_POLL_SECONDS", 3))
        self.worker_id = worker_id or f"{socket.gethostname()}:{os.getpid()}:{uuid.uuid4().hex[:8]}"
        self._tasks: Dict[str, asyncio.Task] = {}
        self._wake = asyncio.Event()
        self._stopping = False
        self._loop_task: Optional[asyncio.Task] = None
        self._maintenance_every = _int_env("JOB_MAINTENANCE_SECONDS", 30)
        self._last_maintenance = 0.0
        # Outcome of scheduling passes (read by /api/admin/health): a pass that
        # hit a database/claim error is a failed pass, not a healthy one.
        self.last_pass_at: Optional[float] = None
        self.last_ok_pass_at: Optional[float] = None
        self.last_pass_ok: Optional[bool] = None
        self.last_pass_error: Optional[str] = None

    # -- lifecycle ---------------------------------------------------------
    def start(self) -> None:
        if self._loop_task is None:
            self._loop_task = asyncio.create_task(self._loop(), name="job-runner")
            logger.info("Job runner started (worker=%s, concurrency=%d)", self.worker_id, self.concurrency)

    async def stop(self) -> None:
        self._stopping = True
        self._wake.set()
        if self._loop_task:
            self._loop_task.cancel()
        # Do not cancel running jobs: their heartbeat stops and another worker
        # (or this one after restart) resumes them.

    def notify(self) -> None:
        """Wake the loop immediately (called after a job is created)."""
        self._wake.set()

    @property
    def active_job_ids(self):
        return list(self._tasks.keys())

    # -- loop --------------------------------------------------------------
    async def _maintenance(self, errors: list) -> None:
        loop = asyncio.get_running_loop()
        now = loop.time()
        if now - self._last_maintenance < self._maintenance_every:
            return
        self._last_maintenance = now
        try:
            requeued, failed = await asyncio.to_thread(job_service.requeue_stale_jobs)
            if requeued or failed:
                logger.warning("Job recovery: requeued=%d failed=%d", requeued, failed)
        except Exception as exc:
            logger.error("Job recovery sweep failed: %r", exc)
            errors.append(f"recovery sweep: {type(exc).__name__}")
        try:
            refunded = await asyncio.to_thread(job_service.settle_unsettled_terminal_jobs)
            if refunded:
                logger.info("Settlement sweep refunded %d credits", refunded)
        except Exception as exc:
            logger.error("Settlement sweep failed: %r", exc)
            errors.append(f"settlement sweep: {type(exc).__name__}")

    def _record_pass(self, errors: list) -> None:
        self.last_pass_ok = not errors
        self.last_pass_error = "; ".join(errors)[:200] if errors else None
        if not errors:
            self.last_ok_pass_at = time.time()

    async def run_once(self) -> int:
        """One scheduling pass. Returns number of jobs started."""
        self.last_pass_at = time.time()
        errors: list = []
        try:
            await self._maintenance(errors)
            free = self.concurrency - len(self._tasks)
            if free <= 0:
                return 0
            started = 0
            try:
                candidates = await asyncio.to_thread(job_service.list_claimable_job_ids, free * 2)
            except Exception as exc:
                logger.error("Could not list pending jobs: %r", exc)
                errors.append(f"list pending: {type(exc).__name__}")
                return 0
            for job_id in candidates:
                if started >= free:
                    break
                try:
                    claimed = await asyncio.to_thread(job_service.claim_job, job_id, self.worker_id)
                except Exception as exc:
                    logger.error("Claim failed for %s: %r", job_id, exc)
                    errors.append(f"claim: {type(exc).__name__}")
                    continue
                if not claimed:
                    continue
                task = asyncio.create_task(self._run_one(job_id), name=f"job-{job_id}")
                self._tasks[job_id] = task
                started += 1
            return started
        except Exception as exc:
            errors.append(f"pass: {type(exc).__name__}")
            raise
        finally:
            self._record_pass(errors)

    async def _run_one(self, job_id: str) -> None:
        try:
            await self._run_fn(job_id, self.worker_id)
        except Exception as exc:  # run_fn handles its own failures; this is a last resort
            logger.exception("Job %s crashed outside its handler: %r", job_id, exc)
        finally:
            self._tasks.pop(job_id, None)
            self._wake.set()

    async def _loop(self) -> None:
        # First pass immediately so restarted processes resume work quickly.
        self._last_maintenance = -1e9
        while not self._stopping:
            try:
                await self.run_once()
            except Exception as exc:
                logger.error("Job runner pass failed: %r", exc)
            self._wake.clear()
            try:
                await asyncio.wait_for(self._wake.wait(), timeout=self.poll_seconds)
            except asyncio.TimeoutError:
                pass
