from datetime import date
from pydantic import BaseModel


class FarmCreate(BaseModel):
    farm_name: str
    crop_type: str
    planting_date: date


class FarmResponse(BaseModel):
    id: int
    farm_name: str
    crop_type: str
    planting_date: date

class FarmUpdate(BaseModel):
    farm_name: str
    crop_type: str
    planting_date: date