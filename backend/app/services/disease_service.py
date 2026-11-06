import io
import os
import numpy as np
from PIL import Image

try:
    import keras
except ImportError:
    try:
        from tensorflow import keras
    except ImportError:
        keras = None



# ==========================================================
# MODEL
# ==========================================================

MODEL_PATH = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "models",
        "rice_disease_model.keras",
    )
)

# Fallback to inception if rice_disease_model.keras not found
if not os.path.exists(MODEL_PATH):
    FALLBACK_PATH = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "..",
            "..",
            "models",
            "FinalTest_inceptionv3.h5",
        )
    )
    if os.path.exists(FALLBACK_PATH):
        MODEL_PATH = FALLBACK_PATH

CLASS_NAMES = [
    "Brown Spot",
    "Healthy",
    "Leaf Blast",
    "Sheath Blight",
]


_model = None


def get_model():
    """
    Load the disease detection model once and reuse it in memory.
    """
    global _model

    if keras is None:
        raise RuntimeError("Keras / TensorFlow is not installed in the current environment.")

    if _model is None:
        _model = keras.models.load_model(
            MODEL_PATH,
            compile=False,
        )

    return _model


def warm_model():
    """
    Pre-warm the model during backend startup so user requests run immediately.
    """
    try:
        model = get_model()
        dummy = np.zeros((1, 224, 224, 3), dtype=np.float32)
        model.predict(dummy, verbose=0)
    except Exception as e:
        print(f"Warning: Model warm-up skipped: {e}")


# ==========================================================
# IMAGE PREPROCESSING
# ==========================================================

def preprocess_image(image_bytes: bytes):
    """
    Convert uploaded image bytes into the format expected
    by the rice disease CNN model (224x224 RGB, [0, 1] range).
    """

    image = Image.open(
        io.BytesIO(image_bytes)
    ).convert("RGB")

    image = image.resize((224, 224))

    image_array = np.array(image, dtype=np.float32)

    # If using InceptionV3 fallback, [-1, 1], otherwise [0, 1] for rice_disease_model.keras
    if "inception" in MODEL_PATH.lower():
        image_array = (image_array / 127.5) - 1.0
    else:
        image_array = image_array / 255.0

    image_array = np.expand_dims(image_array, axis=0)

    return image_array


# ==========================================================
# PREDICTION
# ==========================================================

def predict_disease(image_bytes: bytes):
    """
    Run fast disease prediction on an image.

    Returns:
        disease_name
        confidence
        scale
        all_predictions
    """

    model = get_model()

    image = preprocess_image(image_bytes)

    outputs = model.predict(
        image,
        verbose=0,
    )

    # Handle both dict outputs (.keras) and list outputs (.h5)
    if isinstance(outputs, dict):
        disease_preds = outputs.get("disease", outputs.get("disease_output", list(outputs.values())[0]))
        scale_preds = outputs.get("severity", outputs.get("severity_output", list(outputs.values())[1] if len(outputs) > 1 else None))
    elif isinstance(outputs, (list, tuple)):
        disease_preds = outputs[0]
        scale_preds = outputs[1] if len(outputs) > 1 else None
    else:
        disease_preds = outputs
        scale_preds = None

    disease_preds = np.asarray(disease_preds)
    predicted_index = int(np.argmax(disease_preds[0]))
    confidence = float(disease_preds[0][predicted_index])
    disease_name = CLASS_NAMES[predicted_index]

    if scale_preds is not None:
        scale_arr = np.asarray(scale_preds)
        if scale_arr.shape[-1] == 10:
            scale = float(np.argmax(scale_arr[0]))
        else:
            scale = float(scale_arr[0][0])
    else:
        scale = 0.0

    all_predictions = {
        CLASS_NAMES[i]: float(disease_preds[0][i])
        for i in range(len(CLASS_NAMES))
    }

    return {
        "disease": disease_name,
        "confidence": confidence,
        "scale": scale,
        "all_predictions": all_predictions,
    }