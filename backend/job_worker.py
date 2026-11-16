"""
Standalone scraping worker.

Run the API with ``JOB_RUNNER_MODE=external`` and start one or more of these:

    python job_worker.py

Each worker claims pending jobs from the shared database, heartbeats while
running, and resumes jobs abandoned by a crashed worker. Stopping a worker
(Ctrl+C / SIGTERM) leaves its jobs to be resumed by the next worker.
"""

import asyncio
import logging
import os
import signal
import sys

os.environ.setdefault("JOB_RUNNER_MODE", "external")  # never start a 2nd runner via main's startup hook

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())


async def _main() -> None:
    import main  # noqa: F401  (configures logging, scraper and run_scraping_job)
    from database import init_database
    from job_runner import JobRunner

    init_database()
    runner = JobRunner(main.run_job_by_id)
    runner.start()

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except (NotImplementedError, RuntimeError):
            pass  # Windows: rely on KeyboardInterrupt
    try:
        await stop.wait()
    finally:
        await runner.stop()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    try:
        asyncio.run(_main())
    except KeyboardInterrupt:
        pass
