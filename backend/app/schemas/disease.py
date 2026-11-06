from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class DiseaseCreate(BaseModel):
    farm_id: int
    disease_name: str
    confidence: Optional[float] = None
    image_url: Optional[str] = None
    symptoms: Optional[str] = None
    cause: Optional[str] = None
    treatment: Optional[str] = None
    prevention: Optional[str] = None

class DiseaseResponse(BaseModel):
    id: int
    farm_id: int
    detected_at: datetime
    disease_name: str
    confidence: Optional[float] = None
    image_url: Optional[str] = None
    symptoms: Optional[str] = None
    cause: Optional[str] = None
    treatment: Optional[str] = None
    prevention: Optional[str] = None
    created_at: datetime