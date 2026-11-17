"""Infinity Leads CRM, Phase 1 (feature flag ``CRM_ENABLED``, default off).

Contract: docs/CRM_PHASE1_CONTRACT.md. ``install`` is the only entry point used by
main.py; it adds the ``/api/crm`` router and changes nothing else.
"""

from typing import Callable


def install(app, get_current_user: Callable) -> None:
    from .router import create_router

    app.include_router(create_router(get_current_user))
