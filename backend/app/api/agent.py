from fastapi import APIRouter, HTTPException

from app.schemas.agent import ChatRequest, ChatResponse, SuggestionResponse

from app.services.agent_service import (
    GROQ_MODEL,
    is_groq_configured,
    process_agent_chat,
)

router = APIRouter(
    prefix="/agent",
    tags=["AI Agent"],
)


@router.post("/chat", response_model=ChatResponse)
async def chat_with_agent(payload: ChatRequest):
    """
    Interact with the Smart Farming AI Assistant.
    Grounds answers in real-time IoT sensors and Supabase historical records.
    Uses Groq API when key is configured, or placeholder fallback otherwise.
    """
    if not payload.message or payload.message.strip() == "":
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    response = await process_agent_chat(
        message=payload.message,
        farm_id=payload.farm_id,
        history=payload.history,
    )
    return response


@router.get("/suggestions", response_model=SuggestionResponse)
def get_prompt_suggestions():
    """
    Returns quick suggested prompts for farmers to tap in the mobile UI.
    """
    return {
        "suggestions": [
            "What is the current soil moisture & temperature?",
            "When was the last watering session?",
            "What crop is planted on my farm?",
            "Were any crop diseases detected recently?",
            "Is the water tank full?",
            "How can I optimize irrigation for my crop?",
        ]
    }


@router.get("/status")
def get_agent_status():
    """
    Returns the agent operational status.
    """
    return {
        "agent_name": "Smart Farming AI Assistant",
        "phase": "Phase 1 - Personal Assistant & Telemetry Grounding",
        "groq_configured": is_groq_configured(),
        "active_model": "Agricultural AI Advisor",
        "message": "Assistant Online",
    }
