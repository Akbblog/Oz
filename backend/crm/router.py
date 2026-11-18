"""FastAPI routes for the CRM (``/api/crm``). See docs/CRM_PHASE1_CONTRACT.md."""

from __future__ import annotations

import logging
from typing import Any, Callable, Dict, Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute

from database import get_db

from . import activities, importer, records, reports, stage_management
from .common import CRMError, check_import_rate, crm_enabled
from .workspace import get_or_create, workspace_payload

logger = logging.getLogger(__name__)

STATUS_PATH = "/api/crm/status"


class CRMRoute(APIRoute):
    """Feature flag before auth, contract-shaped errors, never a raw DB error."""

    def get_route_handler(self) -> Callable:
        original = super().get_route_handler()
        path = self.path

        async def handler(request: Request):
            if path != STATUS_PATH and not crm_enabled():
                return JSONResponse(status_code=404, content={"detail": "CRM is not enabled", "code": "crm_disabled"})
            try:
                return await original(request)
            except CRMError as exc:
                return JSONResponse(status_code=exc.status, content=exc.body())
            except RequestValidationError:
                return JSONResponse(status_code=422, content={
                    "detail": "The request is not valid. Check the fields and try again.", "code": "validation_error"})
            except HTTPException:
                raise
            except Exception:
                logger.exception("CRM request failed: %s %s", request.method, path)
                return JSONResponse(status_code=500, content={
                    "detail": "Something went wrong. Please try again.", "code": "server_error"})

        return handler


def create_router(get_current_user: Callable) -> APIRouter:
    router = APIRouter(prefix="/api/crm", tags=["crm"], route_class=CRMRoute)

    def run(user: Dict[str, Any], fn: Callable) -> Any:
        conn = get_db()
        try:
            ws = get_or_create(conn, user)
            return fn(conn, ws)
        finally:
            try:
                conn.rollback()
            except Exception:
                pass
            conn.close()

    def body_dict(body: Any) -> Dict[str, Any]:
        if not isinstance(body, dict):
            raise CRMError(422, "The request body must be a JSON object.", "validation_error")
        return body

    # ------------------------------------------------------------ status / workspace
    @router.get("/status")
    def crm_status(user: dict = Depends(get_current_user)):
        return {"enabled": crm_enabled()}

    @router.get("/workspace")
    def crm_workspace(user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: workspace_payload(c, ws))

    @router.get("/stages")
    def crm_stages(user: dict = Depends(get_current_user)):
        return run(user, stage_management.list_stages)

    @router.post("/stages")
    def crm_create_stage(body: Any = Body(...), user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: stage_management.create(c, ws, body_dict(body)))

    @router.put("/stages/reorder")
    def crm_reorder_stages(body: Any = Body(...), user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: stage_management.reorder(c, ws, body_dict(body)))

    @router.patch("/stages/{stage_id}")
    def crm_rename_stage(stage_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: stage_management.rename(c, ws, stage_id, body_dict(body)))

    @router.post("/stages/{stage_id}/delete")
    def crm_delete_stage(stage_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: stage_management.delete(c, ws, user, stage_id, body_dict(body)))

    @router.get("/jobs/{job_id}/state")
    def crm_job_state(job_id: str, user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: importer.job_state(c, ws, user, job_id))

    # ------------------------------------------------------------ import
    @router.post("/import")
    def crm_import(body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        check_import_rate(user["id"])
        return run(user, lambda c, ws: importer.run_import(c, ws, user, b))

    @router.post("/import/resolve")
    def crm_import_resolve(body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        check_import_rate(user["id"])
        return run(user, lambda c, ws: importer.resolve(c, ws, user, b))

    # ------------------------------------------------------------ records
    def record_filters(q, stage_id, outcome, archived, type, tag_id, source_job_id, due, sort, limit, cursor, tz):
        return {"q": q, "stage_id": stage_id, "outcome": outcome, "archived": archived, "type": type, "tag_id": tag_id,
                "source_job_id": source_job_id, "due": due, "sort": sort, "limit": limit, "cursor": cursor,
                "tz_offset_minutes": tz}

    @router.get("/records")
    def crm_records(
        q: Optional[str] = None, stage_id: Optional[str] = None, outcome: Optional[str] = None,
        archived: Optional[str] = None, type: Optional[str] = None, tag_id: Optional[str] = None,
        source_job_id: Optional[str] = None, due: Optional[str] = None, sort: Optional[str] = None,
        limit: Optional[str] = None, cursor: Optional[str] = None, tz_offset_minutes: Optional[str] = None,
        user: dict = Depends(get_current_user),
    ):
        f = record_filters(q, stage_id, outcome, archived, type, tag_id, source_job_id, due, sort, limit, cursor,
                           tz_offset_minutes)
        return run(user, lambda c, ws: records.list_records(c, ws, f))

    @router.post("/records")
    def crm_create_record(body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: records.create_record(c, ws, user, b))

    @router.get("/pipeline")
    def crm_pipeline(
        q: Optional[str] = None, tag_id: Optional[str] = None, source_job_id: Optional[str] = None,
        per_stage: Optional[str] = None, tz_offset_minutes: Optional[str] = None,
        user: dict = Depends(get_current_user),
    ):
        f = {"q": q, "tag_id": tag_id, "source_job_id": source_job_id, "per_stage": per_stage,
             "tz_offset_minutes": tz_offset_minutes}
        return run(user, lambda c, ws: records.pipeline(c, ws, f))

    @router.get("/records/{record_id}")
    def crm_record_detail(record_id: str, user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: records.detail(c, ws, record_id))

    @router.patch("/records/{record_id}")
    def crm_patch_record(record_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: records.patch_record(c, ws, user, record_id, b))

    @router.get("/records/{record_id}/events")
    def crm_record_events(record_id: str, cursor: Optional[str] = None, limit: Optional[str] = None,
                          user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: records.list_events(c, ws, record_id, cursor, limit))

    def opt_body(body: Any) -> Dict[str, Any]:
        return {} if body is None else body_dict(body)

    @router.post("/records/{record_id}/stage")
    def crm_stage(record_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: records.move_stage(c, ws, user, record_id, b.get("stage_id"), b.get("version")))

    @router.post("/records/{record_id}/convert")
    def crm_convert(record_id: str, body: Any = Body(None), user: dict = Depends(get_current_user)):
        b = opt_body(body)
        return run(user, lambda c, ws: records.convert(c, ws, user, record_id, b.get("version")))

    @router.post("/records/{record_id}/won")
    def crm_won(record_id: str, body: Any = Body(None), user: dict = Depends(get_current_user)):
        b = opt_body(body)
        return run(user, lambda c, ws: records.mark_won(c, ws, user, record_id, b.get("version")))

    @router.post("/records/{record_id}/lost")
    def crm_lost(record_id: str, body: Any = Body(None), user: dict = Depends(get_current_user)):
        b = opt_body(body)
        return run(user, lambda c, ws: records.mark_lost(c, ws, user, record_id, b))

    @router.post("/records/{record_id}/reopen")
    def crm_reopen(record_id: str, body: Any = Body(None), user: dict = Depends(get_current_user)):
        b = opt_body(body)
        return run(user, lambda c, ws: records.reopen(c, ws, user, record_id, b.get("version")))

    @router.post("/records/{record_id}/archive")
    def crm_archive(record_id: str, body: Any = Body(None), user: dict = Depends(get_current_user)):
        b = opt_body(body)
        return run(user, lambda c, ws: records.archive(c, ws, user, record_id, b.get("version")))

    @router.post("/records/{record_id}/restore")
    def crm_restore(record_id: str, body: Any = Body(None), user: dict = Depends(get_current_user)):
        b = opt_body(body)
        return run(user, lambda c, ws: records.restore(c, ws, user, record_id, b.get("version")))

    @router.delete("/records/{record_id}")
    def crm_delete_record(record_id: str, version: Optional[int] = None,
                          user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: records.delete_record(c, ws, user, record_id, version))

    # ------------------------------------------------------------ notes
    @router.post("/records/{record_id}/notes")
    def crm_add_note(record_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: activities.add_note(c, ws, user, record_id, b))

    @router.patch("/notes/{note_id}")
    def crm_edit_note(note_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: activities.edit_note(c, ws, user, note_id, b))

    # ------------------------------------------------------------ people
    @router.post("/records/{record_id}/people")
    def crm_add_person(record_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: activities.add_person(c, ws, user, record_id, b))

    @router.patch("/people/{person_id}")
    def crm_update_person(person_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: activities.update_person(c, ws, user, person_id, b))

    @router.delete("/people/{person_id}")
    def crm_delete_person(person_id: str, user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: activities.delete_person(c, ws, user, person_id))

    @router.get("/people")
    def crm_people(q: Optional[str] = None, limit: Optional[str] = None, cursor: Optional[str] = None,
                   user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: activities.list_people(c, ws, q, limit, cursor))

    # ------------------------------------------------------------ tags
    @router.get("/tags")
    def crm_tags(user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: activities.list_tags(c, ws))

    @router.post("/tags")
    def crm_create_tag(body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: activities.create_tag(c, ws, user, b))

    @router.put("/records/{record_id}/tags")
    def crm_set_tags(record_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: activities.set_record_tags(c, ws, user, record_id, b))

    # ------------------------------------------------------------ activities
    @router.post("/records/{record_id}/activities")
    def crm_add_activity(record_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: activities.add_activity(c, ws, user, record_id, b))

    @router.patch("/activities/{activity_id}")
    def crm_update_activity(activity_id: str, body: Any = Body(...), user: dict = Depends(get_current_user)):
        b = body_dict(body)
        return run(user, lambda c, ws: activities.update_activity(c, ws, user, activity_id, b))

    @router.post("/activities/{activity_id}/done")
    def crm_activity_done(activity_id: str, body: Any = Body(None), user: dict = Depends(get_current_user)):
        b = opt_body(body)
        return run(user, lambda c, ws: activities.complete_activity(c, ws, user, activity_id, b))

    @router.post("/activities/{activity_id}/reopen")
    def crm_activity_reopen(activity_id: str, user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: activities.reopen_activity(c, ws, user, activity_id))

    @router.get("/agenda")
    def crm_agenda(bucket: Optional[str] = None, tz_offset_minutes: Optional[str] = None, limit: Optional[str] = None,
                   cursor: Optional[str] = None, user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: activities.agenda(c, ws, bucket, tz_offset_minutes, limit, cursor))

    @router.get("/agenda/counts")
    def crm_agenda_counts(tz_offset_minutes: Optional[str] = None, user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: activities.agenda_counts(c, ws, tz_offset_minutes))

    # ------------------------------------------------------------ reports / export
    @router.get("/reports")
    def crm_reports(from_: Optional[str] = Query(None, alias="from"), to: Optional[str] = None,
                    tz_offset_minutes: Optional[str] = None, user: dict = Depends(get_current_user)):
        return run(user, lambda c, ws: reports.reports(c, ws, from_, to, tz_offset_minutes))

    @router.get("/export")
    def crm_export(
        format: Optional[str] = None, q: Optional[str] = None, stage_id: Optional[str] = None,
        outcome: Optional[str] = None, archived: Optional[str] = None, type: Optional[str] = None,
        tag_id: Optional[str] = None, source_job_id: Optional[str] = None, due: Optional[str] = None,
        sort: Optional[str] = None, tz_offset_minutes: Optional[str] = None, user: dict = Depends(get_current_user),
    ):
        f = record_filters(q, stage_id, outcome, archived, type, tag_id, source_job_id, due, sort, None, None,
                           tz_offset_minutes)
        return run(user, lambda c, ws: reports.export(c, ws, format, f))

    return router
