import asyncio

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.device import router as device_router

from app.database import supabase
from app.api.farm import router as farm_router
from app.api.irrigation import router as irrigation_router
from app.api.disease import router as disease_router
from app.api.sensor import router as sensor_router
from app.api.agent import router as agent_router
from app.api.weather import router as weather_router
from app.services.irrigation_monitor import monitor_irrigation


from app.services.disease_service import warm_model


app = FastAPI(
    title="Smart Agriculture API",
    version="1.0.0"
)

app.include_router(device_router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================
# BACKGROUND TASK
# ============================================================

irrigation_monitor_task = None


@app.on_event("startup")
async def startup_event():
    global irrigation_monitor_task

    irrigation_monitor_task = asyncio.create_task(
        monitor_irrigation()
    )

    # Pre-warm disease model in background thread
    asyncio.create_task(asyncio.to_thread(warm_model))


@app.on_event("shutdown")
async def shutdown_event():
    global irrigation_monitor_task

    if irrigation_monitor_task is not None:
        irrigation_monitor_task.cancel()

        try:
            await irrigation_monitor_task
        except asyncio.CancelledError:
            pass


# ============================================================
# API ROUTERS
# ============================================================

app.include_router(farm_router)
app.include_router(irrigation_router)
app.include_router(disease_router)
app.include_router(sensor_router)
app.include_router(agent_router)
app.include_router(weather_router)



# ============================================================
# ROOT
# ============================================================

@app.get("/")
def root():
    return {
        "message": "Smart Agriculture API is running"
    }


# ============================================================
# SUPABASE TEST
# ============================================================

@app.get("/test-supabase")
def test_supabase():
    response = supabase.table("farms").select("*").execute()

    return {
        "message": "Supabase connection successful",
        "farms": response.data
    }