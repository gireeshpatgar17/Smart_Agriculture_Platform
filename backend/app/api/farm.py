from fastapi import APIRouter
from app.database import supabase
from app.schemas.farm import FarmCreate, FarmUpdate

router = APIRouter(
    prefix="/farms",
    tags=["Farms"]
)


@router.get("/")
def get_farms():
    response = supabase.table("farms").select("*").execute()

    return response.data

@router.post("/")
def create_farm(farm: FarmCreate):
    response = supabase.table("farms").insert({
        "farm_name": farm.farm_name,
        "crop_type": farm.crop_type,
        "planting_date": farm.planting_date.isoformat()
    }).execute()

    return response.data

@router.get("/{farm_id}")
def get_farm(farm_id: int):
    response = (
        supabase
        .table("farms")
        .select("*")
        .eq("id", farm_id)
        .execute()
    )

    return response.data
@router.put("/{farm_id}")
def update_farm(farm_id: int, farm: FarmUpdate):
    response = (
        supabase
        .table("farms")
        .update({
            "farm_name": farm.farm_name,
            "crop_type": farm.crop_type,
            "planting_date": farm.planting_date.isoformat()
        })
        .eq("id", farm_id)
        .execute()
    )

    return response.data
    
@router.delete("/{farm_id}")
def delete_farm(farm_id: int):
    irrigation = (
        supabase
        .table("irrigation_history")
        .select("id")
        .eq("farm_id", farm_id)
        .limit(1)
        .execute()
    )

    disease = (
        supabase
        .table("disease_history")
        .select("id")
        .eq("farm_id", farm_id)
        .limit(1)
        .execute()
    )

    if irrigation.data or disease.data:
        return {
            "message": "Farm cannot be deleted because it has historical records."
        }

    response = (
        supabase
        .table("farms")
        .delete()
        .eq("id", farm_id)
        .execute()
    )

    return {
        "message": "Farm deleted successfully",
        "farm": response.data
    }