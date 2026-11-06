from typing import List, Optional
from pydantic import BaseModel, Field


class ChatMessage(BaseModel):
    role: str = Field(..., description="Role of the author: 'user' or 'assistant' or 'system'")
    content: str = Field(..., description="Text content of the message")


class ChatRequest(BaseModel):
    farm_id: int = Field(default=1, description="Target farm ID for querying context")
    message: str = Field(..., description="User query or instruction to the farming assistant")
    history: List[ChatMessage] = Field(default_factory=list, description="Recent conversation history")


class ChatResponse(BaseModel):
    reply: str = Field(..., description="Assistant's answer to the user")
    tools_called: List[str] = Field(default_factory=list, description="Names of tools executed to gather data")
    status: str = Field(default="success", description="Status of the interaction ('success', 'warning', or 'error')")


class SuggestionResponse(BaseModel):
    suggestions: List[str] = Field(..., description="List of prompt suggestions for quick user interaction")
