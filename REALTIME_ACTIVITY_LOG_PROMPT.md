# Real-Time Activity Log System Implementation

## Project Context
You are implementing a real-time activity logging system for **Infinity Leads Pro** - a business scraper API built with FastAPI (Python backend) and Flutter (frontend).

**Current State:**
- Backend: FastAPI with SQLite/MySQL, Background scraping jobs
- Frontend: Flutter web with 2-second polling to /api/jobs/{job_id}
- Database: job_logs table stores activity history
- Problem: Not truly real-time, high latency, network overhead

## Objective
Build a **robust, real-time activity logging system** that broadcasts job updates instantly to connected clients via WebSocket, with HTTP polling fallback.

---

## Implementation Requirements

### 1. WebSocket Connection Manager (Python - FastAPI)
**File**: `backend/websocket_manager.py`

Create a `JobStreamManager` class that:
- Tracks active WebSocket connections per job_id
- Ensures users can ONLY subscribe to their own jobs (verify JWT token)
- Maintains message queue (last 100 messages per job)
- Broadcasts messages to all connected clients for a job
- Handles disconnections gracefully
- Implements heartbeat/ping-pong every 30 seconds
- Auto-closes stale connections after 90 seconds inactivity

**Requirements:**
```python
class JobStreamManager:
    async def connect(job_id, websocket, user_id)
    async def disconnect(job_id, websocket)
    async def broadcast(job_id, message: dict)
    async def get_message_history(job_id, limit=50) -> List[dict]
    async def cleanup_stale_connections()
```

**Message Format:**
```json
{
  "timestamp": "ISO8601",
  "job_id": "uuid",
  "type": "JOB_STARTED|CITY_STARTED|CITY_COMPLETED|BUSINESS_FOUND|PROGRESS_UPDATE|JOB_COMPLETED|JOB_FAILED|JOB_CANCELLED",
  "level": "INFO|PROGRESS|WARNING|ERROR",
  "message": "Human readable message",
  "metadata": {
    "current_city": "string",
    "progress_percent": 0-100,
    "processed_cities": int,
    "total_cities": int,
    "businesses_found": int,
    "elapsed_seconds": int,
    "error_count": int
  }
}
```

---

### 2. Activity Logger Service (Python)
**File**: `backend/activity_logger.py`

Create an `ActivityLogger` class that:
- Accepts log events from the scraper
- **Immediately broadcasts** via WebSocket (non-blocking)
- **Asynchronously inserts** into database (doesn't block scraper)
- Implements structured logging with levels and metadata
- Ensures no updates are lost (queue if broadcast fails)

**Requirements:**
```python
class ActivityLogger:
    async def log(
        job_id: str,
        log_type: str,
        message: str,
        level: str = "INFO",
        metadata: Optional[dict] = None
    ) -> None
    
    async def log_city_start(job_id, city, state, city_index, total)
    async def log_city_complete(job_id, city, state, results_count, idx, total)
    async def log_progress(job_id, processed_cities, total_cities, found_count)
    async def log_error(job_id, error_message, city=None, traceback=None)
    async def log_job_complete(job_id, total_results, elapsed_seconds)
```

**Features:**
- Async DB writes (use asyncio.create_task, don't await)
- UUID timestamp generation
- Automatic metadata enrichment
- Graceful queue management

---

### 3. WebSocket Endpoints (FastAPI routes in main.py)
**New Routes:**

```python
@app.websocket("/ws/jobs/{job_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    job_id: str,
    token: str
)
# - Verify JWT token and job ownership
# - Connect to JobStreamManager
# - Send message history (last 50 messages)
# - Stream live updates
# - Handle disconnections

@app.get("/api/jobs/{job_id}/logs")
async def get_job_logs(
    job_id: str,
    since: Optional[str] = None,  # ISO8601 timestamp
    limit: int = 100,
    current_user: dict = Depends(get_current_user)
)
# - Return logs since timestamp (for reconnection catch-up)
# - Used by frontend fallback polling
# - Supports pagination

@app.get("/api/jobs/{job_id}/status")
async def get_job_status_detailed(
    job_id: str,
    current_user: dict = Depends(get_current_user)
)
# - Return current job status with detailed metrics
# - Include elapsed/remaining time estimates
```

---

### 4. Enhanced Job Status Model
**Update**: `ScrapingJob` model in main.py

Add fields for granular tracking:
```python
class ScrapingJob(BaseModel):
    job_id: str
    status: ScrapingStatus
    progress: int  # 0-100
    
    # Granular tracking
    total_cities: int
    processed_cities: int
    current_city: str
    
    # Results tracking
    businesses_found: int
    current_batch_count: int
    
    # Timing
    created_at: str
    started_at: Optional[str]
    completed_at: Optional[str]
    elapsed_seconds: int
    estimated_remaining_seconds: Optional[int]
    
    # Error info
    error: Optional[str]
    error_count: int
    
    # Activity
    latest_activity: str
    last_activity_time: str
    
    logs: List[str]
    results: List[Dict]
```

---

### 5. Scraper Integration
**Update**: `run_scraping_job()` in main.py

Replace all logging with the new ActivityLogger:

```python
# OLD (at top of function):
cursor.execute("INSERT INTO job_logs ...")

# NEW:
await activity_logger.log_job_start(job_id, len(request.cities_data), request.category)

# Inside city loop:
await activity_logger.log_city_start(job_id, city, state, idx, len(request.cities_data))

results = await scraper.scrape_location(...)

await activity_logger.log_city_complete(
    job_id, city, state, 
    results_count=len(results),
    city_index=idx + 1,
    total_cities=len(request.cities_data)
)

# On completion:
await activity_logger.log_job_complete(job_id, len(all_results), elapsed_seconds)

# On error:
await activity_logger.log_error(job_id, str(e), traceback=traceback.format_exc())
```

**Key Constraint:**
- All activity_logger calls must be `await` (not `add_task`)
- Should not block scraper (use asyncio internally for DB writes)
- No try-catch around logging (let it fail gracefully)

---

### 6. Database Updates
**File**: Create new migration or update existing

```sql
-- Ensure job_logs has necessary columns
ALTER TABLE job_logs ADD COLUMN IF NOT EXISTS log_type VARCHAR(50);
ALTER TABLE job_logs ADD COLUMN IF NOT EXISTS log_level VARCHAR(20);
ALTER TABLE job_logs ADD COLUMN IF NOT EXISTS metadata JSON;

-- Add index for fast retrieval
CREATE INDEX IF NOT EXISTS idx_job_logs_created_at ON job_logs(job_id, created_at DESC);

-- Update jobs table for new fields
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS started_at TEXT;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS processed_cities INT DEFAULT 0;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS error_count INT DEFAULT 0;
```

---

### 7. Resilience Features

**Message Queueing:**
- If WebSocket broadcast fails, store in in-memory queue
- Max 1000 messages per job
- Replay on reconnection

**Database Fallback:**
- Always write to database regardless of WebSocket success
- Use asyncio.create_task (fire-and-forget)

**Connection Recovery:**
- Client detects disconnect after 30 seconds
- Requests logs since last_activity_timestamp
- Resumes WebSocket stream

**Heartbeat:**
- Server sends {"type": "ping"} every 30 seconds
- Client responds with pong
- Disconnect if no activity for 90 seconds

---

## Implementation Steps (In Order)

1. ✅ Create `websocket_manager.py` with `JobStreamManager`
2. ✅ Create `activity_logger.py` with `ActivityLogger`
3. ✅ Add WebSocket endpoint to `main.py`
4. ✅ Add GET `/api/jobs/{job_id}/logs` endpoint
5. ✅ Create database migration for new columns
6. ✅ Update `ScrapingJob` model
7. ✅ Replace logging in `run_scraping_job()` function
8. ✅ Add heartbeat cleanup task to FastAPI startup

---

## Code Quality Requirements

- **Type hints**: All functions must have full type annotations
- **Async/await**: Use proper async patterns, no blocking calls
- **Error handling**: Graceful degradation, fail-safe logging
- **Documentation**: Docstrings for all public methods
- **Testing**: Include example usage comments
- **Performance**: No N+1 queries, minimal memory overhead

---

## Integration Points

**With existing code:**
- JWT verification: Use existing `decode_access_token()`
- DB access: Use existing `get_db()` function
- Rate limiting: Use existing `check_rate_limits()`
- Audit logging: Coordinate with existing `record_audit_event()`

**Frontend expectations:**
- Will connect to `/ws/jobs/{job_id}?token={jwt}`
- Will receive JSON messages with type/message/metadata
- Will poll `/api/jobs/{job_id}/logs?since={timestamp}` on reconnect
- Will gracefully fallback to HTTP polling if WebSocket unavailable

---

## Output Deliverables

Please provide:

1. **websocket_manager.py** - Complete implementation
2. **activity_logger.py** - Complete implementation  
3. **main.py code snippets** - All new endpoints and modifications
4. **Database migration** - SQL for new columns/indexes
5. **Updated ScrapingJob model** - Full class definition
6. **Integration guide** - Exact changes to run_scraping_job()
7. **Example usage** - How frontend will connect and use

---

## Success Criteria

✅ Real-time log delivery (< 100ms latency)
✅ Zero message loss (queue + database backup)
✅ Fallback to HTTP polling if WebSocket fails
✅ Handles 100+ concurrent job streams
✅ Auto-cleanup of stale connections
✅ Implements heartbeat/keepalive
✅ Graceful error handling
✅ Full type safety (no Any types)
✅ Comprehensive docstrings
✅ Works with existing auth/DB systems

---

## Special Notes

- Use Python 3.8+ async patterns (no asyncio.run in FastAPI)
- Maintain backward compatibility with existing polling endpoints
- No external dependencies beyond FastAPI/SQLite/MySQL defaults
- Consider high-latency clients (slow networks)
- Handle rapid job creation/cancellation
- Support job streams from multiple users simultaneously

---

## How to Use This Prompt

### Option 1: Direct Copy-Paste
1. Open Claude 4.6 interface
2. Copy the entire prompt (from "Project Context" to "Special Notes")
3. Paste into the chat
4. Ask: "Please implement this complete system with all the code ready to integrate"

### Option 2: Breakdown Approach
Ask Claude to handle one section at a time:
- "Step 1: Implement websocket_manager.py"
- "Step 2: Create activity_logger.py"
- "Step 3: Add the WebSocket endpoints to main.py"
- etc.

### Option 3: Iterative Refinement
Start with the prompt, then ask Claude clarifying questions:
- "Show me the WebSocket implementation with error handling"
- "How would you handle reconnections and message replay?"
- "What about concurrent WebSocket connections?"
- "How do we ensure no message loss?"

---

## Sample Claude 4.6 Request

```
You are an expert FastAPI Python developer. I need to implement a real-time 
activity logging system for a web scraping application. Here are the detailed 
requirements:

[PASTE THE REQUIREMENTS FROM THIS FILE]

Please implement all the required components with production-ready code that:
1. Has full type hints and docstrings
2. Integrates seamlessly with the existing codebase
3. Handles all edge cases and errors gracefully
4. Includes comprehensive examples
5. Follows async/await best practices

Start with the WebSocket manager, then the activity logger, then all endpoint 
integrations. Provide complete, copy-paste-ready code.
```

---

## Expected Output from Claude

You should receive:
- ✅ Complete `websocket_manager.py` with full implementation
- ✅ Complete `activity_logger.py` with all methods
- ✅ Exact code snippets for FastAPI endpoints
- ✅ Database migration SQL statements
- ✅ Updated data models
- ✅ Integration guide for existing `run_scraping_job()` function
- ✅ Example client code for frontend
- ✅ Error handling strategies
- ✅ Testing approaches

---

**This prompt is specifically engineered to produce production-ready, type-safe code that integrates perfectly with your existing Infinity Leads Pro architecture!** 🚀
