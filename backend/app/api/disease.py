import os
import time
import uuid

from fastapi import APIRouter, UploadFile, File

from app.database import supabase
from app.schemas.disease import DiseaseCreate
from app.services.disease_service import predict_disease


router = APIRouter(
    prefix="/disease",
    tags=["Disease"]
)


# ==========================================================
# DISEASE HISTORY
# ==========================================================

@router.get("/{farm_id}")
def get_disease_history(farm_id: int):
    try:
        response = (
            supabase
            .table("disease_history")
            .select("*")
            .eq("farm_id", farm_id)
            .order("detected_at", desc=True)
            .execute()
        )
        return response.data or []
    except Exception as e:
        print(f"Warning: Could not fetch disease history: {e}")
        return []


# ==========================================================
# CREATE DISEASE RECORD
# ==========================================================

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


# ==========================================================
# AI DISEASE PREDICTION
# ==========================================================

@router.post("/predict")
async def predict_crop_disease(
    file: UploadFile = File(...),
    farm_id: int = 1,
):
    # ------------------------------------------------------
    # Read uploaded image
    # ------------------------------------------------------

    image_bytes = await file.read()

    if not image_bytes:
        return {
            "success": False,
            "message": "Uploaded image is empty."
        }

    # ------------------------------------------------------
    # Run AI prediction
    # ------------------------------------------------------

    prediction = predict_disease(image_bytes)
    

    disease_name = prediction["disease"]
    confidence = prediction["confidence"]
    scale = prediction["scale"]
    all_predictions = prediction["all_predictions"]

    # ------------------------------------------------------
    # Disease advice
    # ------------------------------------------------------

    disease_advice = {
        "Healthy": {
            "status": "Healthy",
            "symptoms": "No significant disease symptoms detected.",
            "cause": "No disease detected.",
            "treatment": "No treatment required.",
            "prevention": (
                "Continue regular monitoring and maintain "
                "proper field conditions."
            ),
            "recommendation": (
                "Your crop appears healthy. Continue regular "
                "monitoring and maintain proper irrigation "
                "and field conditions."
            ),
        },

        "Brown Spot": {
            "status": "Disease Detected",
            "symptoms": (
                "Brown circular or oval spots may appear "
                "on rice leaves."
            ),
            "cause": (
                "Fungal disease commonly associated with "
                "Bipolaris oryzae."
            ),
            "treatment": (
                "Maintain balanced nutrition and apply an "
                "appropriate fungicide when recommended."
            ),
            "prevention": (
                "Use healthy seed, maintain balanced "
                "fertilization, and avoid plant stress."
            ),
            "recommendation": (
                "Monitor affected areas closely and follow "
                "appropriate disease-management practices."
            ),
        },

        "Leaf Blast": {
            "status": "Disease Detected",
            "symptoms": (
                "Spindle-shaped lesions may appear on "
                "rice leaves."
            ),
            "cause": (
                "Fungal infection caused by Magnaporthe oryzae."
            ),
            "treatment": (
                "Apply an appropriate fungicide according to "
                "agricultural recommendations and maintain "
                "proper field conditions."
            ),
            "prevention": (
                "Use resistant varieties and avoid excessive "
                "nitrogen application."
            ),
            "recommendation": (
                "Monitor the crop closely and take appropriate "
                "disease-control measures if symptoms increase."
            ),
        },

        "Sheath Blight": {
            "status": "Disease Detected",
            "symptoms": (
                "Lesions may develop on the leaf sheath near "
                "the water or soil line."
            ),
            "cause": (
                "Fungal disease commonly caused by "
                "Rhizoctonia solani."
            ),
            "treatment": (
                "Improve field conditions and apply an "
                "appropriate fungicide when recommended."
            ),
            "prevention": (
                "Avoid excessive nitrogen and maintain "
                "suitable plant spacing and field conditions."
            ),
            "recommendation": (
                "Monitor the affected area and follow "
                "recommended sheath-blight management practices."
            ),
        },
    }

    advice = disease_advice.get(
        disease_name,
        {
            "status": "Unknown",
            "symptoms": None,
            "cause": None,
            "treatment": None,
            "prevention": None,
            "recommendation": (
                "AI prediction completed. Consult an "
                "agricultural expert for further advice."
            ),
        },
    )

    # ------------------------------------------------------
    # Upload image to Supabase Storage & Save History
    # ------------------------------------------------------
    image_url = None
    saved_record = None

    try:
        extension = os.path.splitext(file.filename or "")[1].lower()

        if extension not in [".jpg", ".jpeg", ".png", ".webp"]:
            extension = ".jpg"

        filename = (
            f"farm_{farm_id}/"
            f"{int(time.time())}_{uuid.uuid4().hex}{extension}"
        )

        content_type = file.content_type or "image/jpeg"

        supabase.storage.from_("disease-images").upload(
            filename,
            image_bytes,
            {
                "content-type": content_type
            },
        )

        image_url = (
            supabase
            .storage
            .from_("disease-images")
            .get_public_url(filename)
        )

        data = {
            "farm_id": farm_id,
            "disease_name": disease_name,
            "confidence": confidence * 100,
            "image_url": image_url,
            "symptoms": advice["symptoms"],
            "cause": advice["cause"],
            "treatment": advice["treatment"],
            "prevention": advice["prevention"],
        }

        response = (
            supabase
            .table("disease_history")
            .insert(data)
            .execute()
        )

        saved_record = response.data[0] if response.data else None
    except Exception as db_err:
        print(f"Warning: Supabase save skipped (offline/unreachable): {db_err}")

    # ------------------------------------------------------
    # Return complete AI result
    # ------------------------------------------------------

    return {
        "success": True,
        "id": saved_record.get("id") if saved_record else None,
        "farm_id": farm_id,
        "disease": disease_name,
        "confidence": confidence,
        "scale": scale,
        "status": advice["status"],
        "image_url": image_url,
        "symptoms": advice["symptoms"],
        "cause": advice["cause"],
        "treatment": advice["treatment"],
        "prevention": advice["prevention"],
        "recommendation": advice["recommendation"],
        "all_predictions": all_predictions,
        "saved_to_db": saved_record is not None,
    }