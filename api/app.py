# app.py — VERSI FINAL (no warning, super aman, 0.5 detik predict)
from flask import Flask, request, jsonify
from flask_cors import CORS
import torch, torch.nn as nn
import torchvision.models as models
import torchvision.transforms as T
from PIL import Image
import io
import os
import math
import numpy as np

app = Flask(__name__)
CORS(app)

CLASSES = ['cocci','healty','ncd','prococci','pcrhealty','pcrncd','pcrsalmo','salmo']
def _get_threshold():
    v = os.environ.get('PREDICT_THRESHOLD')
    try:
        return float(v) if v is not None else 0.92
    except ValueError:
        return 0.92

THRESHOLD = _get_threshold()  # minimum confidence to accept a disease prediction

# Buat ResNet18 + load bobot AMAN
model = models.resnet18(weights=None)
model.fc = nn.Linear(512, 8)
model.load_state_dict(torch.load('best_model.pth', map_location='cpu', weights_only=True))
model.eval()

# Preprocess cepat
transform = T.Compose([
    T.Resize(256),
    T.CenterCrop(224),
    T.ToTensor(),
    T.Normalize(mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225])
])

def feces_likeness(img: Image.Image) -> float:
    # Compute a simple heuristic score for feces-like textures/colors
    # 1) Brownish pixel proportion in HSV
    hsv = img.convert('HSV')
    h, s, v = [np.array(ch) for ch in hsv.split()]
    # Brown hue approx range in degrees: 15-45; PIL H in [0,255] ~ scaled
    h_deg = (h.astype(np.float32) / 255.0) * 360.0
    s_norm = s.astype(np.float32) / 255.0
    v_norm = v.astype(np.float32) / 255.0
    brown_mask = (h_deg >= 15) & (h_deg <= 45) & (s_norm >= 0.3) & (v_norm >= 0.15) & (v_norm <= 0.85)
    brown_ratio = float(brown_mask.mean())

    # 2) Texture measure via simple gradient magnitude on luminance
    gray = img.convert('L')
    g = np.array(gray, dtype=np.float32)
    gx = np.abs(np.diff(g, axis=1))
    gy = np.abs(np.diff(g, axis=0))
    grad_mag = (gx.mean() + gy.mean()) / 2.0 / 255.0

    # 3) Central dominance: feces likely centered; check brown proportion in center crop
    w, h_img = img.size
    cx0 = int(w*0.25); cx1 = int(w*0.75); cy0 = int(h_img*0.25); cy1 = int(h_img*0.75)
    center = img.crop((cx0, cy0, cx1, cy1)).convert('HSV')
    ch, cs, cv = [np.array(ch) for ch in center.split()]
    ch_deg = (ch.astype(np.float32) / 255.0) * 360.0
    cs_norm = cs.astype(np.float32) / 255.0
    cv_norm = cv.astype(np.float32) / 255.0
    center_brown = (ch_deg >= 15) & (ch_deg <= 45) & (cs_norm >= 0.3) & (cv_norm >= 0.15) & (cv_norm <= 0.85)
    center_brown_ratio = float(center_brown.mean())

    # Weighted score
    score = 0.5*brown_ratio + 0.3*center_brown_ratio + 0.2*grad_mag
    return float(score)

def pre(b):
    i = Image.open(io.BytesIO(b)).convert('RGB')
    # simple sanity filter: ensure reasonable size
    if min(i.size) < 64:
        raise ValueError('Image too small')
    # basic blur/noise guard: reject extremely uniform images
    if i.getbbox() is None:
        raise ValueError('Blank image')
    return transform(i).unsqueeze(0)

@app.route('/')
def home():
    return "<h1>AYAM DETECTED!</h1>Kirim foto ke /predict"

@app.route('/health', methods=['GET'])
def health():
    try:
        # quick forward of a zero tensor to ensure model is ready
        with torch.no_grad():
            _ = model(torch.zeros(1,3,224,224))
        return jsonify({'status': 'OK', 'model': 'resnet18', 'classes': len(CLASSES)})
    except Exception:
        return jsonify({'status': 'ERROR'}), 500

@app.route('/predict', methods=['POST'])
def predict():
    try:
        if 'image' not in request.files:
            return jsonify({'status': 'ERROR', 'message': 'Field image not found'}), 400
        file = request.files['image']
        raw = file.read()
        if not raw:
            return jsonify({'status': 'ERROR', 'message': 'Empty file'}), 400

        # compute feces-likeness and apply adjustable gate (soft gate)
        img_rgb = Image.open(io.BytesIO(raw)).convert('RGB')
        like_score = feces_likeness(img_rgb)
        req_like = request.args.get('like_min')
        try:
            like_min = float(req_like) if req_like is not None else 0.15
        except ValueError:
            like_min = 0.15

        # proceed to model, but we can reject early if clearly non-feces
        if like_score < like_min:
            return jsonify({'status': 'NOT_FECES', 'penyakit': 'not_feces', 'like_score': round(like_score,3), 'like_min': like_min})

        x = pre(raw)
        with torch.no_grad():
            logits = model(x)[0]
            p = torch.softmax(logits, 0)
            c, i = torch.max(p, 0)

        conf = c.item()
        idx = i.item()

        # allow dynamic threshold per request if provided via header or query
        req_thr = request.args.get('threshold')
        try:
            thr = float(req_thr) if req_thr is not None else THRESHOLD
        except ValueError:
            thr = THRESHOLD

        # compute uncertainty metrics: entropy and top-2 margin
        probs = p.cpu()
        entropy = -torch.sum(probs * torch.log(probs + 1e-12)).item() / math.log(len(CLASSES))
        top2_vals, top2_idx = torch.topk(probs, k=min(2, len(CLASSES)))
        margin = (top2_vals[0] - top2_vals[1]).item() if top2_vals.shape[0] == 2 else top2_vals[0].item()

        # dynamic params from query
        req_entropy_max = request.args.get('entropy_max')
        req_margin_min = request.args.get('margin_min')
        try:
            entropy_max = float(req_entropy_max) if req_entropy_max is not None else 0.6
        except ValueError:
            entropy_max = 0.6
        try:
            margin_min = float(req_margin_min) if req_margin_min is not None else 0.18
        except ValueError:
            margin_min = 0.18

        # softer combined rule to reduce false negatives:
        # reject if like_score too low OR (conf below thr AND (entropy high OR margin low))
        should_reject = (conf < thr and (entropy > entropy_max or margin < margin_min))

        if should_reject:
            return jsonify({
                'penyakit': 'not_feces',
                'confidence': round(conf, 3),
                'status': 'NOT_FECES',
                'threshold': thr,
                'entropy': round(entropy, 3),
                'margin': round(margin, 3)
            })

        # optional top-3 if requested: ?top3=1
        include_top3 = request.args.get('top3') in ('1','true','True')
        resp = {
            'penyakit': CLASSES[idx],
            'confidence': round(conf, 3),
            'status': 'SUCCESS',
            'threshold': thr,
            'entropy': round(entropy, 3),
            'margin': round(margin, 3),
            'like_score': round(like_score, 3),
            'like_min': like_min
        }
        if include_top3:
            top_vals, top_idx = torch.topk(p, k=min(3, len(CLASSES)))
            resp['top3'] = [
                {
                    'label': CLASSES[top_idx[j].item()],
                    'prob': round(top_vals[j].item(), 3)
                } for j in range(top_vals.shape[0])
            ]
        return jsonify(resp)
    except ValueError as e:
        return jsonify({'status': 'ERROR', 'message': str(e)}), 400
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Internal error'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)