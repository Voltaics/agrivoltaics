FROM pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    WORK_ROOT=/tmp/pipeline_work \
    CAPTURE_ROOT=/tmp/captures

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY align_images.py /app/align_images.py
COPY process_images_new.py /app/process_images_new.py
COPY run_inference.py /app/run_inference.py
COPY firebase_upload.py /app/firebase_upload.py
COPY cloud_server.py /app/cloud_server.py
COPY pipeline_runner.py /app/pipeline_runner.py

RUN mkdir -p /app/globals /app/model_weights

COPY globals/global_mean.npy /app/globals/global_mean.npy
COPY globals/global_std.npy /app/globals/global_std.npy

COPY model_weights/vine_presence_resnet.pth /app/model_weights/vine_presence_resnet.pth
COPY model_weights/student_resnet18_distilled.pth /app/model_weights/student_resnet18_distilled.pth

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", "--timeout", "0", "cloud_server:app"]
