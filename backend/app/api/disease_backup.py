from fastapi import APIRouter
from app.database import supabase
from app.schemas.disease import DiseaseCreate

router = APIRouter(
    prefix="/disease",
    tags=["Disease"]
)


@router.get("/{farm_id}")
def get_disease_history(farm_id: int):
    response = (
        supabase
        .table("disease_history")
        .select("*")
        .eq("farm_id", farm_id)
        .order("detected_at", desc=True)
        .execute()
    )

    return response.data


@router.post("/")
def create_disease_record(disease: DiseaseCreate):
    data = {
        "farm_id": disease.farm_id,
        "disease_name": disease.disease_name,
        "confidence": disease.confidence,
        "image_url": disease.image_url,
        "symptoms": disease.symptoms,
        "cause": disease.cause,
        "treatment": disease.treatment,
        "prevention": disease.prevention,
    }

    response = (
        supabase
        .table("disease_history")
        .insert(data)
        .execute()
    )

    return response.data