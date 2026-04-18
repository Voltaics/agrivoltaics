import io
import torch
import torch.nn as nn
import numpy as np
from PIL import Image
import torchvision.transforms as transforms
import torchvision.models as models
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title = "OMID Pest Detection API")
DEVICE = torch.device("cpu")
MODEL_PATH = "pest_presence_resnet.pth"

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"],
)

CLASS_NAMES = [
    "Adult Spotted Laternfly",
    "Early Nypmh Spotted Laternfly",
    "Green Leafhopper",
    "No Pests",
    "Japanese Beetle",
    "Late Nypmh Spotted Laternfly"
]

class PestPresenceResNet18(nn.Module):
    def __init__(self):
        super().__init__()
        self.model = models.resnet18(weights=None)
        in_features = self.model.fc.in_features
        self.model.fc = nn.Linear(in_features, len(CLASS_NAMES))

    def forward(self, x):
        return self.model(x)

# Load the model
model = PestPresenceResNet18().to(DEVICE)
model.load_state_dict(torch.load(MODEL_PATH, map_location=DEVICE))
model.eval()

normalize = transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])

@app.post("/pests_predict")
async def predict_pest(file: UploadFile = File(...)):
    try:
        image = Image.open(io.BytesIO(await file.read()))
        image = image.convert("RGB")

        image_np = np.array(image).astype(np.float32) / 255.0
        image_tensor = torch.tensor(image_np).permute(2, 0, 1)
        image_tensor = normalize(image_tensor).unsqueeze(0).to(DEVICE)

        with torch.no_grad():
            output = model(image_tensor)
            probabilities = torch.softmax(output[0], dim=0)
            conf, pred = torch.max(probabilities, 0)

        return JSONResponse(
            content={
                "success": True,
                "prediction": CLASS_NAMES[pred.item()],
                "confidence": float(conf.item())
            }
        )
    except Exception as e:
        return JSONResponse(
            content={
                "success": False,
                "error": str(e)
            },
            status_code=500
)
