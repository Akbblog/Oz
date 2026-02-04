from __future__ import annotations

from celery import Celery

import config


celery_app = Celery(
    "infinity_leads_pro",
    broker=config.CELERY_CONFIG["broker_url"],
    backend=config.CELERY_CONFIG["result_backend"],
)

celery_app.conf.update(**config.CELERY_CONFIG)

celery_app.conf.beat_schedule = {
    "reconcile-processing-transactions": {
        "task": "background.tasks.reconcile_processing_transactions",
        "schedule": 60.0,
    },
}

